# Factorio AI

This a Factorio mod that attempts to play the game by itself using the controls available to the player.

This is work-in-progress, not yet published on Factorio mod portal. I am working on a good pathfinder algorithm, which is required for anything else. The mod is controlled via console commands:

* `/start` -- the character will go to the closest coal patch and will hand-mine it
* `/stop` -- the mod will stop doing whatever it is doing 
* `/test` -- run unit-tests

## Pathfinding

Pathfinding in Factorio world is quite complicated.

The map is divided into tiles, but the character location is fractional, with granularity of 1/256 of the tile side in each direction. One step of a character can take it 38/256 horizontally or vertically or (27/256, 27/256) diagonally (which is roughly the same speed).

The character and entities have collision boxes, again aligned to 1/256 of a tile. Collision boxes of cliffs can be rotated by 45°. If a collision happens, the character is pushed in some direction that helps him to avoid the obstacle. (I didn't manage to reverse-engineer the exact algorithm for avoiding obstacles, so the AI just avoids bumping into things.)

To deal with it, the pathfinding works as follows:

0. Each position is packed into a single double to save memory, reduce pressure on GC, make them directly comparable and hashable. Positions are only unpacked when we need to do some geometry using their coordinates. Even moving a point by a vector is done without unpacking, by simple addition.

1. The obstacles are represented either as horizontal rectangles (boxes) or as arbitrary convext polygons (WIP).

2. (WIP) To avoid calculating collisions between two shapes, the obstacle collision boxes (or polygons) are expanded by half the size of the collision box of the character. That way the character can be treated as a single point.

3. (WIP) We are using *oct-distance* between points: `abs(dx - dy) + min(dx, dy) * sqrt(2)`, which is roughtly proportional to the number of steps needed to walk from point A to point B by taking steps in one of 8 directions. This metric is quite close to the normal Euclidean distance.

4. The pathfinding algorithm finds a shortest path from a given point to any point within certain radius from any one of a set of goal points. This is more practical than finding point-to-point path because a) the character moves with discreet steps, so it's difficult to get to an exact point, b) we need to be only within certain radius to perform most game actions like mining, c) often we need to reach any one of a set of points (for instance tiles with minable resource), and we do not know a priori which will be closer.

5. The set of goals is represented as a special `PointSet` structure, that can find a nearest point from a set in `log(N)` operations instead of `N`.

6. The actual pathfinding is done via a two-tier A* search algorithm. The top tier algorithm is looking for the shortest path *by tiles*, using the raw distance as a heuristic. The low tier is actually looking for step-by-step path for the character, using the estimation from high-tier path as a heuristic. Both algorithms use caching as much as possible to avoid recalculating paths.