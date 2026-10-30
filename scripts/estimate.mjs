import { AbiCoder, Interface, getCreateAddress, keccak256, toBeHex, parseUnits } from 'ethers';
import { artifact, provider, checkLegacy, owners, OWNER, LEGACY, IDS, legacyABI, quote, fail } from './common.mjs';

// Read-only RPC simulations. No private key and no transactions required.
try {
  const rpc = await provider();
  const legacy = await checkLegacy(rpc);
  if ((await owners(legacy)).some(owner => owner !== OWNER)) throw new Error('This estimate assumes all 50 originals are still in the owner account');
  const compiled = artifact();
  const future = getCreateAddress({ from: OWNER, nonce: await rpc.getTransactionCount(OWNER) });
  const old = new Interface(legacyABI);
  const modern = new Interface(compiled.abi);
  const encode = AbiCoder.defaultAbiCoder();
  const slot = (type, value, index) => keccak256(encode.encode([type, 'uint256'], [value, index]));
  const estimate = async (transaction, overrides) => BigInt(await rpc.send('eth_estimateGas', [
    { from: OWNER, ...transaction }, 'latest', ...(overrides ? [overrides] : []),
  ]));
  const deploy = await estimate({ data: compiled.bytecode.object });
  const transfer = id => ({ to: LEGACY, data: old.encodeFunctionData('transfer', [future, id]) });
  const balances = (sender, recipient) => ({ [LEGACY]: { stateDiff: {
    [slot('address', OWNER, 4)]: toBeHex(sender, 32),
    [slot('address', future, 4)]: toBeHex(recipient, 32),
  } } });
  const first = await estimate(transfer(0));
  const middle = await estimate(transfer(1), balances(49, 1));
  const last = await estimate(transfer(49), balances(1, 49));
  const deposits = first + 48n * middle + last;
  const wrap = await estimate({ to: future, data: modern.encodeFunctionData('wrap', [IDS]) }, {
    [future]: { code: compiled.deployedBytecode.object },
    [LEGACY]: { stateDiff: Object.fromEntries(IDS.map(id => [slot('uint256', id, 6), toBeHex(future, 32)])) },
  });
  const gasPrice = (await rpc.getFeeData()).gasPrice;
  const block = await rpc.getBlockNumber();
  console.log(`Ethereum block ${block}; conservative RPC gas estimates, including transaction overhead`);
  console.log(`Deployment (1 tx): ${quote(deploy, gasPrice)}`);
  console.log(`Original deposits (50 tx): ${quote(deposits, gasPrice)}`);
  console.log(`Receipt minting (1 tx): ${quote(wrap, gasPrice)}`);
  const total = deploy + deposits + wrap;
  console.log(`Total (52 tx): ${quote(total, gasPrice)}`);
  for (const gwei of ['1', '5', '10', '20']) console.log(quote(total, parseUnits(gwei, 'gwei')));
} catch (error) { fail(error); }
