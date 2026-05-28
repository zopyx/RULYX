const path = require("path");

exports.config = {
  runner: "local",
  framework: "mocha",
  mochaOpts: { ui: "bdd", timeout: 60000 },
  specs: ["./test/specs/**/*.js"],
  capabilities: [
    {
      platformName: "iOS",
      "appium:automationName": "XCUITest",
      "appium:deviceName": "iPhone 16 Pro Max",
      "appium:platformVersion": "18.2",
      "appium:app": path.join(__dirname, "../build/Build/Products/Debug-iphonesimulator/RULYX.app"),
      "appium:noReset": false,
      "appium:showXcodeLog": false,
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
};
