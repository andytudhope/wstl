import { ZeroAddress, getAddress } from 'ethers';
import { provider, signer, wrapper, owners, IDS, quote, fail } from './common.mjs';

try {
  if (process.argv.length !== 3) throw new Error('Usage: npm run transfer -- 0xRecipientAddress');
  const to = getAddress(process.argv[2]);
  if (to === ZeroAddress) throw new Error('Recipient cannot be the zero address');
  const rpc = await provider();
  const wallet = signer(rpc, null);
  const from = await wallet.getAddress();
  if (to === from) throw new Error('Recipient is already the sending wallet');
  const tokens = (await wrapper(rpc)).connect(wallet);
  if (await tokens.totalSupply() !== 50n) throw new Error('Finish wrapping all 50 originals before bulk transfer');
  const heldBy = await owners(tokens);
  const ids = IDS.filter(id => heldBy[id] === from);
  if (ids.length) {
    const gas = await tokens.batchTransfer.estimateGas(to, ids);
    const fees = await rpc.getFeeData();
    console.log(`Send ${ids.length} wrapped NFTs from ${from} to ${to}`);
    console.log(quote(gas, fees.maxFeePerGas ?? fees.gasPrice));
    const tx = await tokens.batchTransfer(to, ids, { gasLimit: gas * 120n / 100n });
    console.log(`Transaction: ${tx.hash}`);
    const receipt = await tx.wait();
    console.log(`Transferred ${ids.length} wrapped NFTs; ${receipt.gasUsed} gas`);
  } else {
    console.log(`No wrapped NFTs owned by ${from}; nothing to transfer`);
  }
} catch (error) { fail(error); }
