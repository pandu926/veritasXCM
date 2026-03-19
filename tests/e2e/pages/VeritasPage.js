/**
 * Page Object Model for VeritasXCM main page.
 * Encapsulates all selectors and actions for the single-page dApp.
 */
class VeritasPage {
  constructor(page) {
    this.page = page;

    // Header
    this.headerTitle = page.locator(".header__title");
    this.headerSubtitle = page.locator(".header__subtitle");
    this.connectWalletBtn = page.locator("#connectWalletBtn");
    this.connectedState = page.locator("#connectedState");
    this.statusText = page.locator("#statusText");
    this.statusDot = page.locator("#statusDot");

    // Stats
    this.statCards = page.locator(".stat-card");
    this.statTests = page.locator("#statTests");
    this.statParachains = page.locator("#statParachains");
    this.statContracts = page.locator("#statContracts");

    // Verify Form
    this.verifyPanel = page.locator("#verifyPanel");
    this.assetIdInput = page.locator("#assetId");
    this.originChainInput = page.locator("#originChain");
    this.amountInput = page.locator("#amount");
    this.verifyBtn = page.locator("#verifyBtn");
    this.verifyBtnText = page.locator(".btn-verify__text");
    this.verifyBtnLoading = page.locator(".btn-verify__loading");
    this.readStateBtn = page.locator("#readStateBtn");

    // Quick Fill Buttons
    this.quickBtnAdot = page.locator(
      'button.quick-btn:has-text("aDOT / Acala")',
    );
    this.quickBtnIbtc = page.locator(
      'button.quick-btn:has-text("iBTC / Interlay")',
    );
    this.quickBtnVdot = page.locator(
      'button.quick-btn:has-text("vDOT / Bifrost")',
    );
    this.quickBtnXcdot = page.locator(
      'button.quick-btn:has-text("xcDOT / Moonbeam")',
    );
    this.quickButtons = page.locator(".quick-btn");

    // Result Panel
    this.resultPanel = page.locator("#resultPanel");
    this.resultEmpty = page.locator("#resultEmpty");
    this.resultContent = page.locator("#resultContent");
    this.scoreValue = page.locator("#scoreValue");
    this.scoreRingFill = page.locator("#scoreRingFill");
    this.resultBadge = page.locator("#resultBadge");
    this.badgeIcon = page.locator("#badgeIcon");
    this.badgeText = page.locator("#badgeText");
    this.resultMessage = page.locator("#resultMessage");
    this.txHashLink = page.locator("#txHashLink");

    // Result Details
    this.detailAsset = page.locator("#detailAsset");
    this.detailOrigin = page.locator("#detailOrigin");
    this.detailVerifiedAt = page.locator("#detailVerifiedAt");
    this.detailAnomaly = page.locator("#detailAnomaly");

    // History
    this.historySection = page.locator("#historySection");
    this.historyTable = page.locator("#historyTable");
    this.historyBody = page.locator("#historyBody");
    this.historyRows = page.locator("#historyBody tr");

    // Footer
    this.footer = page.locator(".footer");
  }

  async goto() {
    await this.page.goto("/");
    await this.page.waitForLoadState("domcontentloaded");
  }

  async fillAssetForm(assetId, originChain, amount) {
    await this.assetIdInput.fill(assetId);
    await this.originChainInput.fill(originChain);
    await this.amountInput.fill(String(amount));
  }

  async clickQuickFill(name) {
    const btnMap = {
      aDOT: this.quickBtnAdot,
      iBTC: this.quickBtnIbtc,
      vDOT: this.quickBtnVdot,
      xcDOT: this.quickBtnXcdot,
    };
    await btnMap[name].click();
  }

  async submitVerification() {
    await this.verifyBtn.click();
  }

  async readLatestState() {
    await this.readStateBtn.click();
  }

  async connectWallet() {
    await this.connectWalletBtn.click();
  }

  async getFormValues() {
    return {
      assetId: await this.assetIdInput.inputValue(),
      originChain: await this.originChainInput.inputValue(),
      amount: await this.amountInput.inputValue(),
    };
  }

  async getHistoryRowCount() {
    return this.historyRows.count();
  }

  async isResultVisible() {
    return this.resultContent.isVisible();
  }

  async isEmptyStateVisible() {
    return this.resultEmpty.isVisible();
  }
}

module.exports = { VeritasPage };
