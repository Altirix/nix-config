// Runs in every frame before the page's own scripts (servers/playwright.nix, --init-script). A driven browser
// reports navigator.webdriver = true, the first thing a bot check reads; report what a person's browser does.
if (navigator.webdriver) {
  Object.defineProperty(Navigator.prototype, 'webdriver', { get: () => false, configurable: true });
}
