export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
export const TOKEN_OPTIONS = ["sepoliaeth", "fate"];

export function tokenAddressFor(tokenMode, fateTokenAddress) {
  return tokenMode === "fate" ? fateTokenAddress : ZERO_ADDRESS;
}

export function tokenDisplayName(tokenModeOrAddress, fateTokenAddress = "") {
  if (tokenModeOrAddress === "fate" || sameAddress(tokenModeOrAddress, fateTokenAddress)) {
    return "FATE";
  }
  return "SepoliaETH";
}

export function formatNative(value) {
  return `${value} SepoliaETH`;
}

function sameAddress(left, right) {
  return Boolean(left && right && left.toLowerCase() === right.toLowerCase());
}
