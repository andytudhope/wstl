import { provider, signer, wrapper, checkLegacy, owners, IDS, OWNER, quote, fail } from './common.mjs';

try {
  const args = process.argv.slice(2);
  if (args.length > 1 || (args.length === 1 && (!/^(0|[1-9][0-9]*)$/.test(args[0]) || Number(args[0]) >= 50))) {
    throw new Error('Usage: npm run wrap -- [token ID 0..49]; omit the ID to wrap all remaining tokens');
  }
  const selected = args.length ? [Number(args[0])] : IDS;
  const rpc = await provider();
  const wallet = signer(rpc);
  const receipt = (await wrapper(rpc)).connect(wallet);
  const legacy = (await checkLegacy(rpc)).connect(wallet);
  const address = await receipt.getAddress();
  const heldBy = await owners(legacy);
  for (const id of selected) {
    if (heldBy[id] !== OWNER && heldBy[id] !== address) throw new Error(`Original #${id} is owned by ${heldBy[id]}`);
  }
  console.log(`Permanently depositing original IDs ${selected.join(', ')} into ${address}`);
  for (const id of selected) {
    if (heldBy[id] === address) continue;
    const gas = await legacy.transfer.estimateGas(address, id);
    const tx = await legacy.transfer(address, id, { gasLimit: gas * 120n / 100n });
    console.log(`Deposit #${id}: ${tx.hash}`);
    await tx.wait();
  }
  // ownerOf reverts for unminted receipts; only that ERC721 error means "not wrapped".
  const pending = [];
  for (const id of selected) {
    try { await receipt.ownerOf(id); }
    catch (error) {
      const data = error.data ?? error.info?.error?.data;
      if (typeof data !== 'string' || receipt.interface.parseError(data)?.name !== 'ERC721NonexistentToken') throw error;
      pending.push(id);
    }
  }
  if (pending.length) {
    const gas = await receipt.wrap.estimateGas(pending);
    console.log(`Mint ${pending.length} receipts: ${quote(gas, (await rpc.getFeeData()).gasPrice)}`);
    const tx = await receipt.wrap(pending, { gasLimit: gas * 120n / 100n });
    console.log(`Wrap: ${tx.hash}`);
    await tx.wait();
  }
  const finalOwners = await owners(legacy);
  if (selected.some(id => finalOwners[id] !== address) || (!args.length && await receipt.totalSupply() !== 50n)) {
    throw new Error('Final custody/supply check failed');
  }
  for (const id of selected) await receipt.ownerOf(id);
  console.log(`Original IDs ${selected.join(', ')} are locked and their ERC721 receipts exist. Already minted receipts keep their current owners.`);
} catch (error) { fail(error); }
