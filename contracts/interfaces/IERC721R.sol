// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IERC721R {
    error ERC721R__Expired();
    error ERC721R__InvalidReveal();
    error ERC721R__TransferFailed();
    error ERC721R__InvalidHouseSeed();
    error ERC721R__InvalidSignature();
    error ERC721R__TokenIdUnexisted();
    error ERC721R__RevealPhaseExpired();
    error ERC721R__RevealPhaseNotYetStarted();

    enum Rarity {
        CUP,
        MASCOT,
        QATAR,
        SHOE,
        BALL
    }

    struct CommitInfo {
        bytes32 commitment;
        uint256 blockNumberStart;
        uint256 blockNumberEnd;
    }

    event NewBaseURI(address indexed operator, string baseURI);
    event NewBaseExtension(address indexed operator, string extension);

    event NewCost(
        address indexed operator,
        uint256 indexed oldCost,
        uint256 indexed newCost
    );

    event AttributePercentageMaskUpdated(
        address indexed operator,
        uint256 indexed rarity,
        uint64[] mask
    );

    event Withdrawn(address indexed operator, uint256 indexed value);

    event NewRoot(
        address indexed operator,
        bytes32 indexed oldRoot,
        bytes32 indexed newRoot
    );

    event NewSigner(
        address indexed operator,
        address indexed oldSigner,
        address indexed newSigner
    );

    event Commited(
        address indexed user,
        uint256 indexed revealStart,
        uint256 indexed revealEnd,
        bytes32 commit
    );

    event Unboxed(
        address indexed user,
        uint256 indexed tokenId,
        uint256 indexed rarity,
        uint256 attributeId
    );

    function setRoot(bytes32 root_) external;

    function setSigner(address signer_) external;

    function setBaseURI(string memory _newBaseURI) external;

    function setBaseExtension(string memory _newBaseExtension) external;

    function commit(bytes32 commitment_) external;

    function updateAttributePercentMask(
        uint256 rarity_,
        uint64[] memory percentageMask_
    ) external;

    function mintRandom(
        uint256 userSeed_,
        bytes32 houseSeed_,
        bytes32[] calldata proofs_
    ) external;

    function metadataOf(
        uint256 tokenId_
    ) external view returns (uint256 rarity_, uint256 attributeId_);

    function mintRandom(
        uint256 userSeed_,
        bytes32 houseSeed_,
        uint256 deadline_,
        bytes calldata signature_
    ) external;
}
