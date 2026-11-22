// Runs in every frame before the page's own scripts (servers/playwright.nix, --init-script). Under Playwright, Firefox
// reports navigator.webdriver = true whatever its prefs say, the first thing a bot check reads (Chromium doesn't, once
// AutomationControlled is off). Answer false through a Proxy of the real getter, which still prints as native code.
(() => {
  const descriptor = Object.getOwnPropertyDescriptor(Navigator.prototype, 'webdriver');
  if (!descriptor || !descriptor.get) return;
  Object.defineProperty(Navigator.prototype, 'webdriver', {
    ...descriptor,
    get: new Proxy(descriptor.get, { apply: () => false }),
  });
})();
