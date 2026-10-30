// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {StatusLoversArt} from "./StatusLoversArt.sol";
import {StatusLoversMetadata} from "./StatusLoversMetadata.sol";

interface ILegacyStatusLovers {
    function ownerOf(uint256 id) external view returns (address);
}

/// @notice Permanent custody of originals 0..49; receipts always mint to their original owner.
contract StatusLoversWrapper is ERC721, ReentrancyGuardTransient {
    address public constant LEGACY = StatusLoversMetadata.LEGACY;
    address public constant ORIGINAL_OWNER = StatusLoversMetadata.MINTER;
    uint256 public constant MAX_SUPPLY = 50;
    string public constant ORIGINAL_CID = StatusLoversMetadata.ORIGINAL_CID;
    uint256 public totalSupply;

    struct Rescue {
        uint64 blockNumber;
        uint64 timestamp;
    }

    mapping(uint256 => Rescue) public rescues;
    mapping(address => uint256) public deposits;

    constructor() ERC721(StatusLoversMetadata.COLLECTION_NAME, "wSTL") {
        require(msg.sender == ORIGINAL_OWNER, "Wrong deployer");
    }

    receive() external payable {
        deposits[msg.sender] += msg.value;
    }

    function withdraw() external nonReentrant {
        uint256 amount = deposits[msg.sender];
        require(amount != 0, "No deposit");
        deposits[msg.sender] = 0;
        (bool ok,) = payable(msg.sender).call{value: amount}("");
        require(ok, "ETH withdrawal failed");
    }

    /// @notice Exchange all 50 receipts for this buyer's entire deposit, atomically.
    function bulkSale(address buyer, uint256 expectedDeposit) external nonReentrant {
        require(msg.sender == ORIGINAL_OWNER, "Only seller");
        uint256 amount = deposits[buyer];
        require(amount != 0 && amount == expectedDeposit, "Deposit changed");
        deposits[buyer] = 0;
        for (uint256 id; id < MAX_SUPPLY; ++id) {
            _safeTransfer(ORIGINAL_OWNER, buyer, id);
        }
        (bool ok,) = payable(ORIGINAL_OWNER).call{value: amount}("");
        require(ok, "ETH payment failed");
    }

    /// @dev Transfer originals here with legacy.transfer(address(this), id) first.
    /// Anyone may finalize a deposit, but cannot choose who receives the receipt.
    function wrap(uint256[] calldata ids) external {
        for (uint256 i; i < ids.length; ++i) {
            uint256 id = ids[i];
            require(id < MAX_SUPPLY, "Not an original 50");
            require(ILegacyStatusLovers(LEGACY).ownerOf(id) == address(this), "Original not deposited");
            _mint(ORIGINAL_OWNER, id);
            rescues[id] = Rescue(uint64(block.number), uint64(block.timestamp));
        }
        totalSupply += ids.length;
    }

    /// @notice Send any of your wrapped tokens in one transaction.
    function batchTransfer(address to, uint256[] calldata ids) external {
        for (uint256 i; i < ids.length; ++i) {
            safeTransferFrom(msg.sender, to, ids[i]);
        }
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        _requireOwned(id);
        Rescue memory rescue = rescues[id];
        return StatusLoversMetadata.tokenURI(id, rescue.blockNumber, rescue.timestamp);
    }

    function contractURI() external pure returns (string memory) {
        return StatusLoversMetadata.contractURI();
    }

    /// @notice Deterministic, self-contained artwork; also available before a token is wrapped.
    function artwork(uint256 id) public pure returns (string memory) {
        require(id < MAX_SUPPLY, "Not an original 50");
        return StatusLoversArt.svg(id);
    }
}
