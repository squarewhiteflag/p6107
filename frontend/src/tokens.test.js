import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { ZERO_ADDRESS, formatNative, tokenAddressFor, tokenDisplayName } from "./tokens.js";

describe("token helpers", () => {
  it("maps SepoliaETH to the native token address", () => {
    assert.equal(tokenAddressFor("sepoliaeth", "0xfate"), ZERO_ADDRESS);
  });

  it("keeps FATE mapped to the configured ERC-20 address", () => {
    assert.equal(tokenAddressFor("fate", "0xfate"), "0xfate");
  });

  it("labels native testnet balances as SepoliaETH", () => {
    assert.equal(tokenDisplayName("sepoliaeth"), "SepoliaETH");
    assert.equal(formatNative("1.25"), "1.25 SepoliaETH");
  });
});
