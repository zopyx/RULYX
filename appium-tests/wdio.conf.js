const os = require("os");

exports.config = {
  runner: "local",
  framework: "mocha",
  mochaOpts: { ui: "bdd", timeout: 60000 },
  specs: ["./test/specs/**/*.js"],
  maxInstances: 1,
  specFileRetries: 0,
  capabilities: [
    {
      platformName: "iOS",
      "appium:automationName": "XCUITest",
      "appium:deviceName": "iPhone 16 Pro Max",
      "appium:platformVersion": "18.5",
      "appium:app": path.join(os.homedir(), "Library/Developer/Xcode/DerivedData/RULYX-fsjorrvgvnharicfoawfelgkcvrm/Build/Products/Debug-iphonesimulator/RULYX.app"),
      "appium:language": "en",
      "appium:locale": "en_US",
      "appium:noReset": false,
      "appium:showXcodeLog": false,
      "appium:processArguments": {
        "args": ["--uitesting"]
      },
    },
  ],
  logLevel: "info",
  reporters: ["spec"],
  services: [
    [
      "appium",
      {
        args: { address: "127.0.0.1", port: 4723 },
        command: "appium",
      },
    ],
  ],
  before: async () => {
    await driver.pause(2000);
  },
};
