// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StatusLoversWrapper} from "../src/StatusLoversWrapper.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract BatchReceiver is IERC721Receiver {
    uint256 public received;
    bool private rejectSecond;

    constructor(bool rejectSecond_) {
        rejectSecond = rejectSecond_;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        ++received;
        require(!rejectSecond || received != 2, "Rejected second token");
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract EscrowBuyer is IERC721Receiver {
    StatusLoversWrapper public wrapper;
    bool public rejectSecondNFT;
    bool public rejectETH;
    bool public reenter;
    uint256 public received;
    uint256 public blocked;

    constructor(StatusLoversWrapper wrapper_) {
        wrapper = wrapper_;
    }

    function configure(bool rejectNFT, bool rejectRefund, bool attack) external {
        rejectSecondNFT = rejectNFT;
        rejectETH = rejectRefund;
        reenter = attack;
    }

    function withdraw() external {
        wrapper.withdraw();
    }

    receive() external payable {
        require(!rejectETH, "ETH rejected");
        if (reenter) attemptWithdrawal();
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        ++received;
        require(!rejectSecondNFT || received != 2, "NFT rejected");
        if (reenter) attemptWithdrawal();
        return IERC721Receiver.onERC721Received.selector;
    }

    function attemptWithdrawal() private {
        (bool ok, bytes memory error) = address(wrapper).call(abi.encodeWithSelector(wrapper.withdraw.selector));
        require(!ok && bytes4(error) == bytes4(keccak256("ReentrancyGuardReentrantCall()")), "Reentry not blocked");
        ++blocked;
    }
}

interface Vm {
    function etch(address, bytes calldata) external;
    function store(address, bytes32, bytes32) external;
    function readFile(string calldata) external view returns (string memory);
    function parseBytes(string calldata) external pure returns (bytes memory);
    function prank(address) external;
    function expectRevert() external;
    function envOr(string calldata, string calldata) external view returns (string memory);
    function createSelectFork(string calldata, uint256) external returns (uint256);
    function roll(uint256) external;
    function warp(uint256) external;
    function deal(address, uint256) external;
}

interface Legacy {
    function ownerOf(uint256) external view returns (address);
    function balanceOf(address) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address, uint256) external;
    function transferFrom(address, address, uint256) external;
}

contract StatusLoversWrapperTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address constant OWNER = 0x5f3371793285920351344a1EaaAA48d45e600652;
    address constant BUYER = address(0xBEEF);
    Legacy constant legacy = Legacy(0x5bB0A11b5dDc8E83c21C09FD34cAF49a18E91232);
    StatusLoversWrapper wrapper;

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC_URL", string(""));
        if (bytes(rpc).length != 0) {
            vm.createSelectFork(rpc, 26253872);
        } else {
            // Replay the real runtime with the relevant mainnet storage at block 26253872.
            vm.etch(address(legacy), vm.parseBytes(vm.readFile("test/fixtures/legacy.hex")));
            vm.store(address(legacy), bytes32(0), bytes32(uint256(uint160(OWNER))));
            vm.store(address(legacy), bytes32(uint256(3)), bytes32(uint256(50)));
            vm.store(address(legacy), keccak256(abi.encode(OWNER, uint256(4))), bytes32(uint256(50)));
            uint256 start = uint256(keccak256(abi.encode(uint256(3))));
            for (uint256 id; id < 50; ++id) {
                vm.store(address(legacy), keccak256(abi.encode(id, uint256(6))), bytes32(uint256(uint160(OWNER))));
                vm.store(
                    address(legacy),
                    bytes32(start + id),
                    0x491cefc086eba40f46f5ad79b60c1a550b09875a200378fa7225553829cec902
                );
            }
        }
        require(legacy.totalSupply() == 50 && legacy.balanceOf(OWNER) == 50, "Bad legacy state");
        vm.prank(OWNER);
        wrapper = new StatusLoversWrapper();
    }

    function ids(uint256 start, uint256 count) internal pure returns (uint256[] memory result) {
        result = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            result[i] = start + i;
        }
    }

    function deposit(uint256 start, uint256 count) internal {
        for (uint256 id = start; id < start + count; ++id) {
            vm.prank(OWNER);
            legacy.transfer(address(wrapper), id);
        }
    }

    function depositETH(address buyer, uint256 amount) internal {
        vm.deal(buyer, amount);
        vm.prank(buyer);
        (bool ok,) = address(wrapper).call{value: amount}("");
        require(ok, "Deposit failed");
    }

    function testAll50BackedAndTradeable() public {
        deposit(0, 50);
        // A third party finalizing deposits cannot take the receipts.
        vm.prank(BUYER);
        wrapper.wrap(ids(0, 50));
        require(wrapper.totalSupply() == 50 && wrapper.balanceOf(OWNER) == 50, "Bad receipt supply");
        require(legacy.balanceOf(address(wrapper)) == 50 && legacy.balanceOf(OWNER) == 0, "Bad custody");
        for (uint256 id; id < 50; ++id) {
            require(legacy.ownerOf(id) == address(wrapper) && wrapper.ownerOf(id) == OWNER, "Bad backing");
        }
        require(wrapper.supportsInterface(0x01ffc9a7), "Missing ERC165");
        require(wrapper.supportsInterface(0x80ac58cd), "Missing ERC721");
        require(wrapper.supportsInterface(0x5b5e139f), "Missing metadata");
        vm.prank(OWNER);
        wrapper.setApprovalForAll(address(this), true);
        wrapper.safeTransferFrom(OWNER, BUYER, 49);
        require(wrapper.ownerOf(49) == BUYER && legacy.ownerOf(49) == address(wrapper), "Sale broke backing");
    }

    function testCannotWrapWithoutDeposit() public {
        vm.expectRevert();
        wrapper.wrap(ids(0, 1));
        require(wrapper.totalSupply() == 0, "Unbacked mint");
    }

    function testCannotWrapTwiceOrStealAfterSale() public {
        deposit(0, 1);
        wrapper.wrap(ids(0, 1));
        vm.prank(OWNER);
        wrapper.transferFrom(OWNER, BUYER, 0);
        vm.expectRevert();
        wrapper.wrap(ids(0, 1));
        require(wrapper.ownerOf(0) == BUYER && wrapper.totalSupply() == 1, "Duplicate mint");
    }

    function testRejectsLaterLegacyMint() public {
        // Use the real old mint selector; extra originals remain possible but cannot be wrapped.
        vm.prank(OWNER);
        (bool ok,) = address(legacy).call(abi.encodeWithSelector(bytes4(0xb5f1710f), ids(123, 1), ids(1, 1)));
        require(ok && legacy.totalSupply() == 51 && legacy.ownerOf(50) == OWNER, "Legacy mint failed");
        deposit(50, 1);
        vm.expectRevert();
        wrapper.wrap(ids(50, 1));
    }

    function testBatchFailureIsAtomic() public {
        deposit(0, 1);
        vm.expectRevert();
        wrapper.wrap(ids(0, 2));
        require(wrapper.totalSupply() == 0 && wrapper.balanceOf(OWNER) == 0, "Partial batch mint");
        (uint64 rescueBlock, uint64 rescueTime) = wrapper.rescues(0);
        require(rescueBlock == 0 && rescueTime == 0, "Failed batch left rescue record");
        wrapper.wrap(ids(0, 1));
    }

    function testInterruptedDepositCanResume() public {
        deposit(0, 13);
        wrapper.wrap(ids(0, 13));
        deposit(13, 37);
        wrapper.wrap(ids(13, 37));
        require(wrapper.totalSupply() == 50, "Resume failed");
    }

    function testOriginalOwnerCannotWithdrawLockedOriginal() public {
        deposit(0, 1);
        wrapper.wrap(ids(0, 1));
        vm.prank(OWNER);
        vm.expectRevert();
        legacy.transfer(OWNER, 0);
        vm.prank(OWNER);
        vm.expectRevert();
        legacy.transferFrom(address(wrapper), OWNER, 0);
    }

    function testMetadataRequiresMintedToken() public {
        vm.expectRevert();
        wrapper.tokenURI(0);
        deposit(0, 1);
        wrapper.wrap(ids(0, 1));
        require(bytes(wrapper.tokenURI(0)).length > 100, "Missing metadata");
        vm.expectRevert();
        wrapper.tokenURI(50);
    }

    function testArtworkIsDeterministicAndUniqueForAll50() public view {
        bytes32[50] memory hashes;
        for (uint256 id; id < 50; ++id) {
            string memory svg = wrapper.artwork(id);
            hashes[id] = keccak256(bytes(svg));
            require(hashes[id] == keccak256(bytes(wrapper.artwork(id))), "Artwork changed");
            for (uint256 other; other < id; ++other) {
                require(hashes[id] != hashes[other], "Duplicate artwork");
            }
        }
    }

    function testArtworkRejectsNonOriginalIds() public {
        vm.expectRevert();
        wrapper.artwork(50);
        vm.expectRevert();
        wrapper.artwork(type(uint256).max);
    }

    function testBatchTransfersAll50AndNextOwnerCanSendAgain() public {
        deposit(0, 50);
        wrapper.wrap(ids(0, 50));
        vm.prank(OWNER);
        wrapper.approve(address(this), 0);
        vm.prank(OWNER);
        wrapper.batchTransfer(BUYER, ids(0, 50));
        require(wrapper.balanceOf(OWNER) == 0 && wrapper.balanceOf(BUYER) == 50, "Bad batch balances");
        require(wrapper.getApproved(0) == address(0), "Approval not cleared");
        require(wrapper.totalSupply() == 50, "Supply changed");
        for (uint256 id; id < 50; ++id) {
            require(wrapper.ownerOf(id) == BUYER && legacy.ownerOf(id) == address(wrapper), "Bad custody");
        }
        vm.prank(BUYER);
        wrapper.batchTransfer(OWNER, ids(0, 50));
        require(wrapper.balanceOf(OWNER) == 50 && wrapper.balanceOf(BUYER) == 0, "Next owner cannot batch");
    }

    function testBatchCannotTakeSomeoneElsesTokens() public {
        deposit(0, 1);
        wrapper.wrap(ids(0, 1));
        vm.prank(BUYER);
        vm.expectRevert();
        wrapper.batchTransfer(BUYER, ids(0, 1));
        require(wrapper.ownerOf(0) == OWNER, "Unauthorized transfer");
    }

    function testBatchFailureRollsBackEarlierTransfers() public {
        deposit(0, 2);
        wrapper.wrap(ids(0, 2));
        vm.prank(OWNER);
        wrapper.transferFrom(OWNER, address(this), 1);
        vm.prank(OWNER);
        vm.expectRevert();
        wrapper.batchTransfer(BUYER, ids(0, 2));
        require(wrapper.ownerOf(0) == OWNER && wrapper.ownerOf(1) == address(this), "Partial transfer");
        require(wrapper.balanceOf(BUYER) == 0, "Buyer kept part of failed batch");
    }

    function testBatchAcceptsERC721Receiver() public {
        deposit(0, 2);
        wrapper.wrap(ids(0, 2));
        BatchReceiver receiver = new BatchReceiver(false);
        vm.prank(OWNER);
        wrapper.batchTransfer(address(receiver), ids(0, 2));
        require(receiver.received() == 2 && wrapper.balanceOf(address(receiver)) == 2, "Receiver not called");
    }

    function testBatchReceiverRejectionRollsBackEverything() public {
        deposit(0, 2);
        wrapper.wrap(ids(0, 2));
        BatchReceiver receiver = new BatchReceiver(true);
        vm.prank(OWNER);
        vm.expectRevert();
        wrapper.batchTransfer(address(receiver), ids(0, 2));
        require(wrapper.balanceOf(OWNER) == 2 && wrapper.balanceOf(address(receiver)) == 0, "Partial receiver batch");
        require(receiver.received() == 0, "Receiver state not reverted");
    }

    function testBatchRejectsZeroAndNonReceiverContract() public {
        deposit(0, 1);
        wrapper.wrap(ids(0, 1));
        vm.prank(OWNER);
        vm.expectRevert();
        wrapper.batchTransfer(address(0), ids(0, 1));
        vm.prank(OWNER);
        vm.expectRevert();
        wrapper.batchTransfer(address(this), ids(0, 1));
        require(wrapper.ownerOf(0) == OWNER, "Token lost");
    }

    function testRescueRecordsActualBlockAndTimeForEachBatch() public {
        deposit(0, 2);
        vm.roll(27000000);
        vm.warp(1800000000);
        wrapper.wrap(ids(0, 1));
        (uint64 firstBlock, uint64 firstTime) = wrapper.rescues(0);
        require(firstBlock == 27000000 && firstTime == 1800000000, "Wrong first rescue record");
        vm.roll(27000042);
        vm.warp(1800000504);
        wrapper.wrap(ids(1, 1));
        (uint64 secondBlock, uint64 secondTime) = wrapper.rescues(1);
        require(secondBlock == 27000042 && secondTime == 1800000504, "Wrong second rescue record");
        (firstBlock, firstTime) = wrapper.rescues(0);
        require(firstBlock == 27000000 && firstTime == 1800000000, "First record changed");
    }

    function testRescueAndMetadataStayFixedAfterSaleAndFailedRewrap() public {
        deposit(0, 1);
        vm.roll(27000000);
        vm.warp(1800000000);
        wrapper.wrap(ids(0, 1));
        bytes32 originalURI = keccak256(bytes(wrapper.tokenURI(0)));
        vm.prank(OWNER);
        wrapper.batchTransfer(BUYER, ids(0, 1));
        vm.roll(28000000);
        vm.warp(1900000000);
        vm.expectRevert();
        wrapper.wrap(ids(0, 1));
        (uint64 rescueBlock, uint64 rescueTime) = wrapper.rescues(0);
        require(rescueBlock == 27000000 && rescueTime == 1800000000, "Rescue overwritten");
        require(keccak256(bytes(wrapper.tokenURI(0))) == originalURI, "Metadata changed after rescue");
    }

    function testCollectionMetadataAvailableBeforeWrappingAndStaysFixed() public {
        bytes32 collection = keccak256(bytes(wrapper.contractURI()));
        deposit(0, 1);
        vm.roll(27000000);
        vm.warp(1800000000);
        wrapper.wrap(ids(0, 1));
        require(keccak256(bytes(wrapper.contractURI())) == collection, "Collection metadata changed");
    }

    function testOnlyOriginalOwnerCanDeploy() public {
        vm.expectRevert();
        new StatusLoversWrapper();
    }

    function testEscrowTopUpsAndDepositorsAreIndependent() public {
        depositETH(BUYER, 1 ether);
        depositETH(BUYER, 2 ether);
        depositETH(address(0xCAFE), 4 ether);
        require(wrapper.deposits(BUYER) == 3 ether, "Top-up lost");
        require(wrapper.deposits(address(0xCAFE)) == 4 ether, "Other deposit changed");
        require(address(wrapper).balance == 7 ether, "Wrong escrow balance");
    }

    function testEscrowFullWithdrawalOnlyOnceAndOnlyOwnFunds() public {
        depositETH(BUYER, 3 ether);
        depositETH(address(0xCAFE), 2 ether);
        vm.prank(OWNER);
        vm.expectRevert();
        wrapper.withdraw();
        vm.prank(BUYER);
        wrapper.withdraw();
        require(BUYER.balance == 3 ether && wrapper.deposits(BUYER) == 0, "Refund incomplete");
        require(
            address(wrapper).balance == 2 ether && wrapper.deposits(address(0xCAFE)) == 2 ether, "Other funds taken"
        );
        vm.prank(BUYER);
        vm.expectRevert();
        wrapper.withdraw();
    }

    function testEscrowSaleExchangesAll50ForOnlyThisBuyersFullDeposit() public {
        deposit(0, 50);
        wrapper.wrap(ids(0, 50));
        depositETH(BUYER, 3 ether);
        depositETH(address(0xCAFE), 2 ether);
        uint256 before = OWNER.balance;
        vm.prank(OWNER);
        wrapper.bulkSale(BUYER, 3 ether);
        require(OWNER.balance == before + 3 ether, "Seller not paid");
        require(wrapper.deposits(BUYER) == 0 && wrapper.balanceOf(BUYER) == 50, "Sale incomplete");
        for (uint256 id; id < 50; ++id) {
            require(wrapper.ownerOf(id) == BUYER && legacy.ownerOf(id) == address(wrapper), "Backing changed");
        }
        vm.prank(BUYER);
        vm.expectRevert();
        wrapper.withdraw();
        vm.prank(address(0xCAFE));
        wrapper.withdraw();
        require(address(0xCAFE).balance == 2 ether && address(wrapper).balance == 0, "Other buyer cannot refund");
    }

    function testEscrowSaleRejectsUnauthorizedCallerAndEmptyDeposit() public {
        depositETH(BUYER, 3 ether);
        vm.prank(BUYER);
        vm.expectRevert();
        wrapper.bulkSale(BUYER, 3 ether);
        vm.prank(OWNER);
        vm.expectRevert();
        wrapper.bulkSale(address(0xCAFE), 0);
        require(wrapper.deposits(BUYER) == 3 ether, "Unauthorized payment");
    }

    function testEscrowSaleRejectsChangedDepositIncludingWithdrawalAndRedeposit() public {
        deposit(0, 50);
        wrapper.wrap(ids(0, 50));
        depositETH(BUYER, 3 ether);
        vm.prank(OWNER);
        vm.expectRevert();
        wrapper.bulkSale(BUYER, 2 ether);
        vm.prank(BUYER);
        wrapper.withdraw();
        depositETH(BUYER, 1 wei);
        vm.prank(OWNER);
        vm.expectRevert();
        wrapper.bulkSale(BUYER, 3 ether);
        require(wrapper.deposits(BUYER) == 1 wei && wrapper.balanceOf(OWNER) == 50, "Stale price accepted");
    }

    function testEscrowSaleRequiresAll50Receipts() public {
        deposit(0, 49);
        wrapper.wrap(ids(0, 49));
        depositETH(BUYER, 3 ether);
        vm.prank(OWNER);
        vm.expectRevert();
        wrapper.bulkSale(BUYER, 3 ether);
        require(wrapper.balanceOf(OWNER) == 49 && wrapper.balanceOf(BUYER) == 0, "Partial lot sold");
        require(wrapper.deposits(BUYER) == 3 ether, "Partial lot charged");
    }

    function testEscrowSaleRollsBackWhenOneReceiptHasAnotherOwner() public {
        deposit(0, 50);
        wrapper.wrap(ids(0, 50));
        vm.prank(OWNER);
        wrapper.transferFrom(OWNER, address(0xCAFE), 49);
        depositETH(BUYER, 3 ether);
        vm.prank(OWNER);
        vm.expectRevert();
        wrapper.bulkSale(BUYER, 3 ether);
        require(wrapper.balanceOf(OWNER) == 49 && wrapper.balanceOf(BUYER) == 0, "Partial sale committed");
        require(wrapper.ownerOf(49) == address(0xCAFE) && wrapper.deposits(BUYER) == 3 ether, "Funds or token taken");
    }

    function testEscrowNFTRejectionRestoresDepositAndEarlierTransfers() public {
        deposit(0, 50);
        wrapper.wrap(ids(0, 50));
        EscrowBuyer buyer = new EscrowBuyer(wrapper);
        buyer.configure(true, false, false);
        depositETH(address(buyer), 3 ether);
        vm.prank(OWNER);
        vm.expectRevert();
        wrapper.bulkSale(address(buyer), 3 ether);
        require(wrapper.balanceOf(OWNER) == 50 && wrapper.deposits(address(buyer)) == 3 ether, "Partial failed sale");
        require(buyer.received() == 0, "Receiver state not rolled back");
        buyer.withdraw();
        require(address(buyer).balance == 3 ether, "Failed sale blocked refund");
    }

    function testEscrowFailedSellerPaymentRollsBackNFTsAndDeposit() public {
        deposit(0, 50);
        wrapper.wrap(ids(0, 50));
        depositETH(BUYER, 3 ether);
        vm.etch(OWNER, hex"60006000fd");
        vm.prank(OWNER);
        vm.expectRevert();
        wrapper.bulkSale(BUYER, 3 ether);
        require(wrapper.balanceOf(OWNER) == 50 && wrapper.balanceOf(BUYER) == 0, "Unpaid NFT transfer");
        require(wrapper.deposits(BUYER) == 3 ether && address(wrapper).balance == 3 ether, "Failed payment lost ETH");
    }

    function testEscrowFailedRefundPreservesCredit() public {
        EscrowBuyer buyer = new EscrowBuyer(wrapper);
        buyer.configure(false, true, false);
        depositETH(address(buyer), 3 ether);
        vm.expectRevert();
        buyer.withdraw();
        require(wrapper.deposits(address(buyer)) == 3 ether, "Failed refund lost credit");
        buyer.configure(false, false, false);
        buyer.withdraw();
        require(address(buyer).balance == 3 ether, "Retry refund failed");
    }

    function testEscrowRefundReentryCannotTakeAnotherDepositorsFunds() public {
        EscrowBuyer buyer = new EscrowBuyer(wrapper);
        buyer.configure(false, false, true);
        depositETH(address(buyer), 3 ether);
        depositETH(address(0xCAFE), 2 ether);
        buyer.withdraw();
        require(buyer.blocked() == 1 && address(buyer).balance == 3 ether, "Refund reentry not blocked");
        require(
            wrapper.deposits(address(buyer)) == 0 && wrapper.deposits(address(0xCAFE)) == 2 ether, "Escrow corrupted"
        );
    }

    function testEscrowNFTCallbackCannotWithdrawDuringSale() public {
        deposit(0, 50);
        wrapper.wrap(ids(0, 50));
        EscrowBuyer buyer = new EscrowBuyer(wrapper);
        buyer.configure(false, false, true);
        depositETH(address(buyer), 3 ether);
        uint256 before = OWNER.balance;
        vm.prank(OWNER);
        wrapper.bulkSale(address(buyer), 3 ether);
        require(buyer.blocked() == 50 && buyer.received() == 50, "NFT callback reentry not blocked");
        require(OWNER.balance == before + 3 ether && wrapper.deposits(address(buyer)) == 0, "Sale not settled");
    }

    function testGiftBatchDoesNotSpendBuyersDeposit() public {
        deposit(0, 50);
        wrapper.wrap(ids(0, 50));
        depositETH(BUYER, 3 ether);
        vm.prank(OWNER);
        wrapper.batchTransfer(BUYER, ids(0, 50));
        require(wrapper.deposits(BUYER) == 3 ether, "Gift spent deposit");
        vm.prank(BUYER);
        wrapper.withdraw();
        require(BUYER.balance == 3 ether, "Gift blocked refund");
    }
}
