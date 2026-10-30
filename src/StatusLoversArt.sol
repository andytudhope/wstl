// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @dev Palette and original heart path: https://status.app/brand
library StatusLoversArt {
    using Strings for uint256;

    function svg(uint256 id) internal pure returns (string memory) {
        return render(id, 'width="3000" height="3000" viewBox="0 0 1000 1000"');
    }

    function banner() internal pure returns (string memory) {
        return render(0, 'width="3000" height="1200" viewBox="0 300 1000 400"');
    }

    function colorNames(uint256 id) internal pure returns (string memory, string memory, string memory) {
        string[11] memory names =
            ["Blue", "Purple", "Orange", "Army", "Turquoise", "Sky", "Yellow", "Pink", "Copper", "Camel", "Magenta"];
        (, uint256 a, uint256 b, uint256 c) = settings(id);
        return (names[a], names[b], names[c]);
    }

    function settings(uint256 id) private pure returns (uint256 seed, uint256 a, uint256 b, uint256 c) {
        seed = uint256(keccak256(abi.encode("Status Lovers", id)));
        a = seed % 11;
        b = (a + 1 + (seed >> 8) % 10) % 11;
        c = (a + 1 + (seed >> 16) % 10) % 11;
        while (c == a || c == b) c = (c + 1) % 11;
    }

    function render(uint256 id, string memory frame) private pure returns (string memory) {
        (uint256 seed, uint256 a, uint256 b, uint256 c) = settings(id);
        string[11] memory colors = [
            "#2a4af5",
            "#7140fd",
            "#ff7d46",
            "#216266",
            "#2a799b",
            "#1992d7",
            "#f6b03c",
            "#f66f8f",
            "#cb6256",
            "#c78f67",
            "#ec266c"
        ];
        string memory background = string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" ',
            frame,
            ' overflow="hidden">',
            "<title>Status Lovers #",
            id.toString(),
            "</title><defs>",
            '<linearGradient id="b" x1="0" y1="0" x2="1" y2="1" gradientTransform="rotate(',
            ((seed >> 24) % 360).toString(),
            ' .5 .5)">',
            '<stop stop-color="',
            colors[a],
            '"/><stop offset="1" stop-color="',
            colors[b],
            '"/></linearGradient>',
            '<filter id="blur" x="-100%" y="-100%" width="300%" height="300%" color-interpolation-filters="sRGB">',
            '<feGaussianBlur stdDeviation="',
            (65 + (seed >> 32) % 45).toString(),
            '"/></filter>',
            '<radialGradient id="v"><stop offset=".15" stop-color="#09101c" stop-opacity="0"/>',
            '<stop offset="1" stop-color="#09101c" stop-opacity=".46"/></radialGradient></defs>',
            '<rect width="1000" height="1000" fill="url(#b)"/><g filter="url(#blur)">'
        );
        string memory clouds = string.concat(
            cloud(seed >> 40, colors[c], "0.95"),
            cloud(seed >> 88, colors[a], "0.8"),
            cloud(seed >> 136, colors[b], "0.8"),
            cloud(seed >> 184, "#ffffff", "0.16")
        );
        return string.concat(
            background,
            clouds,
            '</g><rect width="1000" height="1000" fill="url(#v)"/>',
            '<g transform="translate(140 140) scale(3)" fill="#ffffff"><path d="',
            "M178.44 111.861C176.767 141.07 150.082 162.602 120.004 165",
            "C89.9269 162.602 63.2437 141.07 61.5716 111.861",
            "C60.5474 93.9256 71.5138 76.0117 89.3221 75.0441",
            "C103.654 74.2939 114.111 83.1492 118.118 98.6021",
            "C119.076 102.253 119.66 105.993 119.859 109.764",
            "C119.903 110.531 119.936 111.285 119.96 112.026",
            "C120.042 111.307 120.107 110.554 120.152 109.764",
            "C120.351 105.993 120.935 102.253 121.894 98.6021",
            "C125.9 83.1492 136.357 74.2939 150.689 75.0441",
            'C168.497 76.0117 179.464 93.9256 178.44 111.861Z"/></g></svg>'
        );
    }

    function cloud(uint256 seed, string memory color, string memory opacity) private pure returns (string memory) {
        return string.concat(
            '<ellipse cx="',
            (seed % 1200).toString(),
            '" cy="',
            ((seed >> 12) % 1200).toString(),
            '" rx="',
            (260 + (seed >> 24) % 340).toString(),
            '" ry="',
            (260 + (seed >> 36) % 340).toString(),
            '" fill="',
            color,
            '" opacity="',
            opacity,
            '"/>'
        );
    }
}
