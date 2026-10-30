import { spawnSync } from 'node:child_process';
import { getAddress, ZeroAddress } from 'ethers';
import { fail } from './common.mjs';

try {
  if (!process.env.ETHERSCAN_API_KEY?.trim()) throw new Error('Set ETHERSCAN_API_KEY in .env');
  if (!process.env.WRAPPER_ADDRESS) throw new Error('Set WRAPPER_ADDRESS in .env');
  const address = getAddress(process.env.WRAPPER_ADDRESS);
  if (address === ZeroAddress) throw new Error('WRAPPER_ADDRESS cannot be zero');
  const result = spawnSync('forge', [
    'verify-contract', '--chain', 'mainnet', '--watch',
    address, 'src/StatusLoversWrapper.sol:StatusLoversWrapper',
  ], { stdio: 'inherit', env: process.env });
  if (result.error) throw result.error;
  process.exitCode = result.status ?? 1;
} catch (error) { fail(error); }
