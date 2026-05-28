describe("navigation", () => {
  it("can tap Settings tab and see the toggle", async () => {
    const settingsTab = await $("~Settings");
    await settingsTab.click();
    await driver.pause(1000);

    const betaToggle = await $("~showBetaFeatures");
    expect(await betaToggle.isDisplayed()).toBe(true);
  });

  it("can enable beta features and see Timeline tab appear", async () => {
    await (await $("~Settings")).click();
    await driver.pause(500);

    const betaSwitch = await $("~showBetaFeatures");
    const currentValue = await betaSwitch.getAttribute("value");
    if (currentValue === "0") {
      await betaSwitch.click();
      await driver.pause(500);
    }

    const timelineTab = await $("~Timeline");
    await timelineTab.waitForDisplayed({ timeout: 5000 });
    expect(await timelineTab.isDisplayed()).toBe(true);
  });
});
