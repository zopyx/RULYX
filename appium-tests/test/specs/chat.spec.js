describe("chat list", () => {
  before(async () => {
    await (await $("~Settings")).click();
    await driver.pause(500);

    const betaSwitch = await $("~showBetaFeatures");
    const currentValue = await betaSwitch.getAttribute("value");
    if (currentValue === "0") {
      await betaSwitch.click();
      await driver.pause(500);
    }
  });

  it("navigates to Chat tab", async () => {
    const chatTab = await $("~Chat");
    await chatTab.click();
    await driver.pause(1000);

    const title = await $("~Chat");
    expect(await title.isDisplayed()).toBe(true);
  });

  it("shows the new chat button", async () => {
    await (await $("~Chat")).click();
    await driver.pause(1000);

    const newBtn = await $("~New conversation");
    await newBtn.waitForDisplayed({ timeout: 5000 });
    expect(await newBtn.isDisplayed()).toBe(true);
  });
});
