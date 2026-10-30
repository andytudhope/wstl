import 'dotenv/config';
import { readFileSync } from 'node:fs';
import { Contract, JsonRpcProvider, NonceManager, Wallet, formatEther, formatUnits } from 'ethers';

export const LEGACY = '0x5bB0A11b5dDc8E83c21C09FD34cAF49a18E91232';
export const OWNER = '0x5f3371793285920351344a1EaaAA48d45e600652';
export const IDS = Array.from({ length: 50 }, (_, id) => id);
export const legacyABI = [
  'function owner() view returns (address)',
  'function totalSupply() view returns (uint256)',
  'function ownerOf(uint256) view returns (address)',
  'function transfer(address,uint256)',
];

export function artifact() {
  return JSON.parse(readFileSync(new URL('../out/StatusLoversWrapper.sol/StatusLoversWrapper.json', import.meta.url)));
}

export async function provider() {
  if (!process.env.RPC_URL) throw new Error('Set RPC_URL in .env');
  const rpc = new JsonRpcProvider(process.env.RPC_URL, undefined, { batchMaxCount: 1 });
  if ((await rpc.getNetwork()).chainId !== 1n) throw new Error('Ethereum mainnet (chain ID 1) required');
  return rpc;
}

export function signer(rpc, expectedOwner = OWNER) {
  const key = process.env.PRIVATE_KEY?.trim().replace(/^0x/i, '');
  if (!/^[0-9a-fA-F]{64}$/.test(key ?? '')) throw new Error('PRIVATE_KEY must be 64 hex characters');
  const wallet = new Wallet(`0x${key}`, rpc);
  if (expectedOwner && wallet.address !== expectedOwner) throw new Error(`PRIVATE_KEY belongs to ${wallet.address}; expected ${expectedOwner}`);
  return new NonceManager(wallet);
}

export async function wrapper(rpc) {
  const address = process.env.WRAPPER_ADDRESS;
  if (!address) throw new Error('Set WRAPPER_ADDRESS in .env');
  const compiled = artifact();
  if (await rpc.getCode(address) !== compiled.deployedBytecode.object) {
    throw new Error('WRAPPER_ADDRESS does not match the locally compiled wrapper');
  }
  return new Contract(address, compiled.abi, rpc);
}

export async function checkLegacy(rpc) {
  const legacy = new Contract(LEGACY, legacyABI, rpc);
  if (await legacy.owner() !== OWNER) throw new Error('Unexpected legacy contract owner');
  // Later legacy mints cannot enter the wrapper. Do not require supply == 50 on resume.
  if (await legacy.totalSupply() < 50n) throw new Error('Original 50 tokens do not exist');
  return legacy;
}

export async function owners(legacy) {
  const result = [];
  // Small batches work with public RPC rate limits.
  for (let i = 0; i < IDS.length; i += 5) {
    result.push(...await Promise.all(IDS.slice(i, i + 5).map(id => legacy.ownerOf(id))));
  }
  return result;
}

export function quote(gas, gasPrice) {
  return `${gas.toLocaleString()} gas; ${formatEther(gas * gasPrice)} ETH at ${formatUnits(gasPrice, 'gwei')} gwei`;
}

export function fail(error) {
  // Never dump the provider/transaction object: it may contain an RPC credential.
  console.error(error.shortMessage ?? error.reason ?? (error.code
    ? `Failed (${error.code}); check configuration, account balance and RPC connectivity.`
    : error.message));
  process.exitCode = 1;
}
