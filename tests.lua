local log = require("util").log

local tests = {}

local function register_test(name, func)
    tests[name] = func
end

local function run_tests()
    for name, func in pairs(tests) do
        func()
        log(name, ': ok')
    end
end

return {
    register_test = register_test,
    run_tests = run_tests
}