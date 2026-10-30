// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {StatusLoversArt} from "./StatusLoversArt.sol";

library StatusLoversMetadata {
    using Strings for uint256;

    string internal constant COLLECTION_NAME = "Status Lovers (Still)";
    address internal constant LEGACY = 0x5bB0A11b5dDc8E83c21C09FD34cAF49a18E91232;
    address internal constant MINTER = 0x5f3371793285920351344a1EaaAA48d45e600652;
    string internal constant ORIGINAL_CID = "QmTG44cVAw4k58BNnb2AZ5PMeFYwRjcZ7qwhhNYzBrsKjP";
    string internal constant MINT_TX = "0x1033ddae896879c0fb092f5c8ae6aa4ffaac16af9cd69a3c2bb45fb578b6927b";
    uint256 internal constant MINT_BLOCK = 4816694;
    uint256 internal constant MINT_TIMESTAMP = 1514527767;

    function tokenURI(uint256 id, uint256 rescueBlock, uint256 rescueTimestamp) internal pure returns (string memory) {
        string memory identity = string.concat(
            '{"name":"Status Lovers #',
            id.toString(),
            '","description":"One of the original 50 Status Lovers tokens minted on Ethereum on 29 December 2017. '
            "This ERC721 permanently holds the corresponding original token and presents new, deterministic onchain artwork. "
            'The original IPFS reference is preserved; original media was not recovered at rescue.",',
            '"external_url":"',
            mintLink(),
            '","image":"',
            imageURI(StatusLoversArt.svg(id)),
            '",'
        );
        string memory original = string.concat(
            '"original_contract":"',
            Strings.toHexString(LEGACY),
            '","original_token_id":"',
            id.toString(),
            '","original_content":"ipfs://',
            ORIGINAL_CID,
            '","wrapped_supply_cap":50,'
        );
        return jsonURI(
            string.concat(
                identity,
                original,
                '"provenance":',
                provenance(rescueBlock, rescueTimestamp),
                ',"artwork":',
                artworkCredit(),
                ',"attributes":',
                attributes(id, rescueBlock, rescueTimestamp),
                "}"
            )
        );
    }

    function contractURI() internal pure returns (string memory) {
        string memory image = imageURI(StatusLoversArt.svg(0));
        return jsonURI(
            string.concat(
                '{"name":"',
                COLLECTION_NAME,
                '","symbol":"wSTL","edition":"Original 50",',
                '"description":"A rescue of the original 50 Status Lovers tokens minted on Ethereum on 29 December 2017. '
                "Each wrapped receipt permanently escrows its matching original. The wrapper is capped at 50 receipts. "
                "New 2026 onchain artwork uses the Status heart and brand palette. The original IPFS reference is preserved; "
                'the original media was not recovered for this rescue.",',
                '"image":"',
                image,
                '","banner_image":"',
                imageURI(StatusLoversArt.banner()),
                '","featured_image":"',
                image,
                '","external_link":"',
                mintLink(),
                '","artwork":',
                artworkCredit(),
                "}"
            )
        );
    }

    function mintLink() private pure returns (string memory) {
        return string.concat("https://etherscan.io/tx/", MINT_TX);
    }

    function provenance(uint256 rescueBlock, uint256 rescueTimestamp) private pure returns (string memory) {
        return string.concat(
            '{"chain_id":1,',
            '"original_deployment_transaction":"0xd5015c18f9e7ced5d9e425d81f1865b1e26981c8b17c99a239a994685b86f653",',
            '"original_deployment_block":4816690,"original_deployment_timestamp":1514527717,',
            '"original_mint_transaction":"',
            MINT_TX,
            '","original_mint_block":4816694,"original_mint_timestamp":1514527767,',
            '"original_minter":"',
            Strings.toHexString(MINTER),
            '","rescue_block":',
            rescueBlock.toString(),
            ',"rescue_timestamp":',
            rescueTimestamp.toString(),
            ',"original_media_status_at_rescue":"Not recovered"}'
        );
    }

    function artworkCredit() private pure returns (string memory) {
        return '{"year":2026,"medium":"Onchain generative SVG","generator":"StatusLoversArt v1",'
            '"logo_credit":"Status","logo_source":"https://status.app/brand"}';
    }

    function attributes(uint256 id, uint256 rescueBlock, uint256 rescueTimestamp) private pure returns (string memory) {
        string memory history = string.concat(
            numberTrait("Original mint date", MINT_TIMESTAMP, true),
            ",",
            numberTrait("Original mint block", MINT_BLOCK, false),
            ",",
            numberTrait("Original token ID", id, false),
            ",",
            textTrait("Edition", "Original 50"),
            ",",
            numberTrait("Wrapped edition size", 50, false)
        );
        string memory rescue = string.concat(
            textTrait("Preservation", "Original permanently escrowed"),
            ",",
            numberTrait("Rescue date", rescueTimestamp, true),
            ",",
            numberTrait("Rescue block", rescueBlock, false),
            ",",
            textTrait("Original media at rescue", "Not recovered")
        );
        (string memory a, string memory b, string memory c) = StatusLoversArt.colorNames(id);
        string memory art = string.concat(
            numberTrait("Artwork year", 2026, false),
            ",",
            textTrait("Artwork", "Onchain generative SVG"),
            ",",
            textTrait("Gradient colour 1", a),
            ",",
            textTrait("Gradient colour 2", b),
            ",",
            textTrait("Accent colour", c)
        );
        return string.concat("[", history, ",", rescue, ",", art, "]");
    }

    function textTrait(string memory name, string memory value) private pure returns (string memory) {
        return string.concat('{"trait_type":"', name, '","value":"', value, '"}');
    }

    function numberTrait(string memory name, uint256 value, bool date) private pure returns (string memory) {
        return string.concat(
            '{"display_type":"', date ? "date" : "number", '","trait_type":"', name, '","value":', value.toString(), "}"
        );
    }

    function imageURI(string memory svg) private pure returns (string memory) {
        return string.concat("data:image/svg+xml;base64,", Base64.encode(bytes(svg)));
    }

    function jsonURI(string memory json) private pure returns (string memory) {
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }
}
