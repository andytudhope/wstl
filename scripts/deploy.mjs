import { writeFileSync, existsSync } from 'node:fs';
import { ContractFactory } from 'ethers';
import { artifact, provider, signer, checkLegacy, owners, OWNER, quote, fail } from './common.mjs';

try {
  const rpc = await provider();
  const wallet = signer(rpc);
  if (existsSync('deployment.json')) throw new Error('deployment.json already exists; use that wrapper or move the file before redeploying');
  const legacy = await checkLegacy(rpc);
  if (await legacy.totalSupply() !== 50n || (await owners(legacy)).some(owner => owner !== OWNER)) {
    throw new Error('Deployment requires exactly 50 originals, all owned by the original owner');
  }
  const compiled = artifact();
  const factory = new ContractFactory(compiled.abi, compiled.bytecode.object, wallet);
  const transaction = await factory.getDeployTransaction();
  const gas = await wallet.estimateGas(transaction);
  const fees = await rpc.getFeeData();
  console.log(`Deploy: ${quote(gas, fees.maxFeePerGas ?? fees.gasPrice)}`);
  const contract = await factory.deploy({ gasLimit: gas * 120n / 100n });
  const tx = contract.deploymentTransaction();
  const address = await contract.getAddress();
  // Save before waiting, so an interrupted process does not lose the address.
  writeFileSync('deployment.json', JSON.stringify({ chainId: 1, address, transaction: tx.hash }, null, 2) + '\n');
  console.log(`Transaction: ${tx.hash}\nWRAPPER_ADDRESS=${address}`);
  const receipt = await tx.wait();
  console.log(`Deployed in block ${receipt.blockNumber}; ${receipt.gasUsed} gas`);
} catch (error) { fail(error); }
