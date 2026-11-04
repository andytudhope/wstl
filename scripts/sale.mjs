import { existsSync, writeFileSync } from 'node:fs';
import { ZeroAddress, formatEther, getAddress, parseEther } from 'ethers';
import { provider, signer, wrapper, owners, OWNER, quote, fail } from './common.mjs';

let rpc;
try {
  if (process.argv.length !== 4) throw new Error('Usage: npm run sale -- 0xBuyerAddress agreedPriceInETH');
  if (existsSync('sale.json')) throw new Error('sale.json already exists; check the recorded transaction before sending another');
  const buyer = getAddress(process.argv[2]);
  const amount = parseEther(process.argv[3]);
  if (buyer === ZeroAddress || buyer === OWNER || amount <= 0n) throw new Error('A buyer address and positive sale price are required');
  rpc = await provider();
  const wallet = signer(rpc);
  const tokens = (await wrapper(rpc)).connect(wallet);
  if (buyer === tokens.target) throw new Error('Buyer cannot be the wrapper');
  const [deposit, supply, heldBy, balance, latestNonce, pendingNonce] = await Promise.all([
    tokens.deposits(buyer), tokens.totalSupply(), owners(tokens), rpc.getBalance(OWNER),
    rpc.getTransactionCount(OWNER, 'latest'), rpc.getTransactionCount(OWNER, 'pending'),
  ]);
  if (deposit !== amount) throw new Error(`Buyer deposit is ${formatEther(deposit)} ETH; expected ${formatEther(amount)} ETH`);
  if (supply !== 50n || heldBy.some(owner => owner !== OWNER)) throw new Error('Seller must own all 50 wrapped NFTs');
  if (latestNonce !== pendingNonce) throw new Error('Seller has pending transactions; wait for them before selling');
  await tokens.bulkSale.staticCall(buyer, amount);
  const gas = await tokens.bulkSale.estimateGas(buyer, amount);
  const fees = await rpc.getFeeData();
  const gasLimit = gas * 120n / 100n;
  if (fees.maxFeePerGas === null || fees.maxPriorityFeePerGas === null) throw new Error('RPC did not return Ethereum fee data');
  if (balance < gasLimit * fees.maxFeePerGas) throw new Error('Insufficient ETH to cover gas');
  console.log(`Sell all 50 wrapped NFTs to ${buyer} for ${formatEther(amount)} ETH`);
  console.log(quote(gas, fees.maxFeePerGas));
  const tx = await tokens.bulkSale(buyer, amount, {
    gasLimit, maxFeePerGas: fees.maxFeePerGas, maxPriorityFeePerGas: fees.maxPriorityFeePerGas,
  });
  const report = { chainId: 1, contract: tokens.target, seller: OWNER, buyer, priceWei: amount.toString(), transaction: tx.hash };
  const save = () => writeFileSync('sale.json', JSON.stringify(report, null, 2) + '\n');
  save(); // Keep the hash even if confirmation or subsequent checks are interrupted.
  console.log(`Transaction: ${tx.hash}`);
  const receipt = await tx.wait(2);
  Object.assign(report, {
    blockNumber: receipt.blockNumber, status: receipt.status, gasUsed: receipt.gasUsed.toString(), feeEth: formatEther(receipt.fee),
  });
  save();
  const [finalOwners, remainingDeposit, buyerCount, sellerCount] = await Promise.all([
    owners(tokens), tokens.deposits(buyer), tokens.balanceOf(buyer), tokens.balanceOf(OWNER),
  ]);
  Object.assign(report, {
    all50OwnedByBuyer: finalOwners.every(owner => owner === buyer), remainingDepositWei: remainingDeposit.toString(),
    buyerTokenCount: buyerCount.toString(), sellerTokenCount: sellerCount.toString(),
  });
  save();
  if (receipt.status !== 1 || !report.all50OwnedByBuyer || remainingDeposit !== 0n || sellerCount !== 0n) {
    throw new Error('Sale was broadcast; review sale.json and onchain state before taking further action');
  }
  console.log(`Confirmed in block ${receipt.blockNumber}: buyer owns all 50 NFTs; ${formatEther(amount)} ETH paid to ${OWNER}`);
  console.log(`Transaction fee: ${report.feeEth} ETH. Receipt saved in sale.json.`);
} catch (error) { fail(error); }
finally { rpc?.destroy(); }
