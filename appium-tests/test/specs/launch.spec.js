describe("RULYX launch", () => {
  it("shows the Moderation tab on launch", async () => {
    const tab = await $("~Moderation");
    await tab.waitForDisplayed({ timeout: 10000 });
    expect(await tab.isDisplayed()).toBe(true);
  });

  it("shows all four default tab bar items", async () => {
    for (const label of ["Moderation", "Info", "Settings", "Accounts"]) {
      const tab = await $(`~${label}`);
      await tab.waitForDisplayed({ timeout: 5000 });
      expect(await tab.isDisplayed()).toBe(true);
    }
  });
});
