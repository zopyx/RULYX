describe("RULYX", () => {
  before(async () => {
    await driver.pause(3000);
  });

  it("launches and shows Moderation tab", async () => {
    const tab = await $("~Moderation");
    await tab.waitForDisplayed({ timeout: 10000 });
    expect(await tab.isDisplayed()).toBe(true);
  });

  it("shows all four default tabs", async () => {
    for (const label of ["Moderation", "Info", "Settings", "Accounts"]) {
      const tab = await $(`~${label}`);
      await tab.waitForDisplayed({ timeout: 5000 });
      expect(await tab.isDisplayed()).toBe(true);
    }
  });
});
