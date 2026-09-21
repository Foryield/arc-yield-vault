"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { formatUnits, parseUnits, type Address, type Hash } from "viem";
import {
  FAUCET_URL,
  NETWORK_LABEL,
  USDC_GAS_RESERVE,
  connectWallet,
  deposit,
  exit,
  explorerAddress,
  explorerTx,
  friendlyError,
  readVault,
  reconnectWallet,
  type VaultState,
} from "@/lib/arc";
import { DEFAULT_VAULT, VAULTS, vaultFromKey, type VaultConfig } from "@/lib/vaults";

type Mode = "deposit" | "redeem";
type Phase = "idle" | "approve" | "deposit" | "redeem" | "success" | "error";

function shorten(address: string) {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

/// Display only: at most four decimals, cut from the exact decimal string (no float rounding).
function display(units: bigint, decimals: number) {
  const [whole, fraction = ""] = formatUnits(units, decimals).split(".");
  const cut = fraction.slice(0, 4).replace(/0+$/, "");
  return cut ? `${whole}.${cut}` : whole;
}

/// Parses the typed amount into base units; null when it is not a positive decimal number.
function parseAmount(text: string, decimals: number): bigint | null {
  if (!/^\d+(\.\d+)?$/.test(text.trim())) return null;
  try {
    const value = parseUnits(text.trim(), decimals);
    return value > 0n ? value : null;
  } catch {
    return null; // more decimals than the asset supports
  }
}

export default function Home() {
  const [vault, setVault] = useState<VaultConfig>(DEFAULT_VAULT);
  const [account, setAccount] = useState<Address | null>(null);
  const [state, setState] = useState<VaultState | null>(null);
  const [mode, setMode] = useState<Mode>("deposit");
  const [amount, setAmount] = useState("1");
  // A full exit redeems the exact share balance: going through a rounded asset amount would
  // leave dust shares behind.
  const [redeemAll, setRedeemAll] = useState(false);
  const [phase, setPhase] = useState<Phase>("idle");
  const [txHash, setTxHash] = useState<Hash | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [unreachable, setUnreachable] = useState(false);

  const { symbol, decimals } = vault.asset;

  // Only the latest read may land: switching vault or account while an older read is in flight
  // must not let that read overwrite the state of the instance now on screen.
  const latestRead = useRef(0);
  const refresh = useCallback(async (v: VaultConfig, a: Address | null) => {
    const id = ++latestRead.current;
    try {
      const next = await readVault(v, a);
      if (id !== latestRead.current) return;
      setState(next);
      setUnreachable(false);
    } catch {
      if (id !== latestRead.current) return;
      setState(null);
      setUnreachable(true);
    }
  }, []);

  // Instance requested by the URL (`?vault=eurc`), then a silent reconnection of the wallet.
  useEffect(() => {
    setVault(vaultFromKey(new URLSearchParams(window.location.search).get("vault")));
    reconnectWallet()
      .then(setAccount)
      .catch(() => {});
    const onAccounts = (accounts: unknown) => {
      const [first] = accounts as Address[];
      setAccount(first ?? null);
    };
    window.ethereum?.on("accountsChanged", onAccounts);
    return () => window.ethereum?.removeListener("accountsChanged", onAccounts);
  }, []);

  useEffect(() => {
    refresh(vault, account);
  }, [vault, account, refresh]);

  function reset() {
    setPhase("idle");
    setTxHash(null);
    setError(null);
    setRedeemAll(false);
  }

  function switchVault(next: VaultConfig) {
    if (next.key === vault.key) return;
    setVault(next);
    setState(null);
    setMode("deposit");
    setAmount("1");
    reset();
    const url = new URL(window.location.href);
    url.searchParams.set("vault", next.key);
    window.history.replaceState(null, "", url.toString());
  }

  function switchMode(next: Mode) {
    if (next === mode) return;
    setMode(next);
    reset();
  }

  async function handleConnect() {
    try {
      setError(null);
      setAccount(await connectWallet());
    } catch (e) {
      setError(friendlyError(e));
    }
  }

  const parsed = parseAmount(amount, decimals);
  const available = state
    ? state.walletBalance - (vault.paysGas ? USDC_GAS_RESERVE : 0n)
    : 0n;

  async function handleSubmit() {
    if (!account || !state) return;
    setError(null);
    setTxHash(null);
    try {
      let hash: Hash;
      if (mode === "deposit") {
        if (parsed === null) return;
        hash = await deposit(vault, account, parsed, setPhase);
      } else {
        setPhase("redeem");
        hash = redeemAll
          ? await exit(vault, account, { all: true, shares: state.shares })
          : await exit(vault, account, { all: false, assets: parsed ?? 0n });
      }
      setTxHash(hash);
      setPhase("success");
      setRedeemAll(false);
      await refresh(vault, account);
    } catch (e) {
      setError(friendlyError(e));
      setPhase("error");
    }
  }

  const busy = phase === "approve" || phase === "deposit" || phase === "redeem";
  const canDeposit = parsed !== null && parsed <= available;
  const canRedeem =
    !!state && state.shares > 0n && (redeemAll || (parsed !== null && parsed <= state.position));
  const canSubmit =
    !!account && !!state && !state.paused && !busy && (mode === "deposit" ? canDeposit : canRedeem);

  const busyLabel =
    phase === "approve"
      ? `Step 1 of 2: approve exactly ${amount} ${symbol}...`
      : phase === "deposit"
        ? "Depositing: confirm in your wallet..."
        : "Redeeming: confirm in your wallet...";

  return (
    <div className="shell">
      <div className="brand">
        <div className="logo">
          For<span>Yield</span> &times; Arc
        </div>
        <div className="badge">{NETWORK_LABEL}</div>
      </div>

      <div className="tabs" role="tablist" aria-label="Vault instance">
        {VAULTS.map((v) => (
          <button
            key={v.key}
            type="button"
            role="tab"
            aria-selected={v.key === vault.key}
            className={v.key === vault.key ? "tab active" : "tab"}
            onClick={() => switchVault(v)}
            disabled={busy}
          >
            {v.tab}
          </button>
        ))}
      </div>

      <div className="card">
        <div className="title">Morpho Yield Vault</div>
        <div className="subtitle">{vault.subtitle}</div>

        {state && (
          <>
            <div className="row">
              <span className="label">Vault total</span>
              <span className="value">
                {display(state.totalAssets, decimals)} {symbol}
              </span>
            </div>
            <div className="row">
              <span className="label">Supplied to Morpho</span>
              <span className="value">
                <a href={explorerAddress(vault.morphoTarget)} target="_blank" rel="noreferrer">
                  {display(state.inMorpho, decimals)} {symbol}
                </a>
              </span>
            </div>
          </>
        )}

        {unreachable && (
          <div className="status error">
            The vault could not be read from Arc testnet: the network is unreachable from this
            browser, or the vault address is misconfigured. Reload the page in a moment.
          </div>
        )}

        {!account ? (
          <button onClick={handleConnect}>Connect wallet</button>
        ) : (
          <>
            <div className="row">
              <span className="label">Wallet</span>
              <span className="value mono">{shorten(account)}</span>
            </div>
            {state && (
              <>
                <div className="row">
                  <span className="label">{symbol} balance</span>
                  <span className="value">
                    {display(state.walletBalance, decimals)} {symbol}
                  </span>
                </div>
                <div className="row">
                  <span className="label">Your vault position</span>
                  <span className="value">
                    {display(state.position, decimals)} {symbol}
                  </span>
                </div>
              </>
            )}

            {state?.paused && (
              <div className="status error">The vault is paused: deposits and exits are closed.</div>
            )}

            <div className="tabs modes">
              <button
                type="button"
                className={mode === "deposit" ? "tab active" : "tab"}
                onClick={() => switchMode("deposit")}
                disabled={busy}
              >
                Deposit
              </button>
              <button
                type="button"
                className={mode === "redeem" ? "tab active" : "tab"}
                onClick={() => switchMode("redeem")}
                disabled={busy}
              >
                Redeem
              </button>
            </div>

            <label className="field" htmlFor="amount">
              {mode === "deposit" ? "Amount to deposit" : "Amount to redeem"}
            </label>
            <div className="input-wrap">
              <input
                id="amount"
                type="text"
                inputMode="decimal"
                value={amount}
                onChange={(e) => {
                  setAmount(e.target.value);
                  setRedeemAll(false);
                }}
                disabled={busy}
              />
              <span className="suffix">{symbol}</span>
            </div>

            {mode === "deposit" && vault.paysGas && (
              <div className="hint">
                USDC also pays gas on Arc: {display(USDC_GAS_RESERVE, decimals)} USDC stays in
                your wallet for fees.
              </div>
            )}

            {mode === "redeem" && state && state.shares > 0n && (
              <button
                type="button"
                className="secondary"
                onClick={() => {
                  setAmount(formatUnits(state.position, decimals));
                  setRedeemAll(true);
                }}
                disabled={busy}
              >
                Redeem everything ({display(state.position, decimals)} {symbol})
              </button>
            )}

            <button onClick={handleSubmit} disabled={!canSubmit}>
              {busy ? (
                <>
                  <span className="spinner" />
                  {busyLabel}
                </>
              ) : mode === "deposit" ? (
                "Deposit"
              ) : (
                "Redeem"
              )}
            </button>

            {state && state.walletBalance === 0n && (
              <div className="status">
                No {symbol} in this wallet.{" "}
                <a href={FAUCET_URL} target="_blank" rel="noreferrer">
                  Get testnet {symbol} from Circle &rarr;
                </a>
              </div>
            )}
          </>
        )}

        {phase === "success" && txHash && (
          <div className="status success">
            {mode === "deposit"
              ? "Deposit confirmed and supplied to Morpho in the same transaction."
              : "Redemption confirmed."}{" "}
            The figures above are up to date.
            <br />
            <a href={explorerTx(txHash)} target="_blank" rel="noreferrer">
              View on the Arc explorer &rarr;
            </a>
          </div>
        )}

        {error && <div className="status error">{error}</div>}

        <div className="links">
          <a href={explorerAddress(vault.address)} target="_blank" rel="noreferrer">
            Vault contract (verified)
          </a>
          <a href="https://github.com/Foryield/arc-yield-vault" target="_blank" rel="noreferrer">
            Source code
          </a>
        </div>
      </div>

      <div className="footer">
        The testnet Morpho Vault V2 targets are real Morpho contracts with no lending market
        attached, so they earn nothing: real Morpho yield is shown against a curated mainnet
        vault in the repository&apos;s fork test.
        <br />
        Testnet demo - Circle Developer Grants - for-yield.com. Testnet tokens only, with no
        value. ForYield is not an authorised crypto-asset service provider; this page is not an
        offer of a financial service.
      </div>
    </div>
  );
}
