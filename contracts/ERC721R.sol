// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/presets/ERC721PresetMinterPauserAutoIdUpgradeable.sol";

import "./interfaces/IERC721R.sol";

/// @custom:security-contact tudo.dev@gmail.com
contract ERC721R is
    IERC721R,
    UUPSUpgradeable,
    EIP712Upgradeable,
    ERC721PresetMinterPauserAutoIdUpgradeable
{
    using ECDSAUpgradeable for *;
    using StringsUpgradeable for *;
    using MerkleProofUpgradeable for *;

    /// @dev value is equal to keccak256("ERC721R_v1")
    bytes32 public constant VERSION =
        0x5e0552f6dd362c5662d2fa5933e126337ae8694639a8f14cda60fa3df2995615;

    /// @dev value is equal to keccak256("UPGRADER_ROLE")
    bytes32 public constant UPGRADER_ROLE =
        0x189ab7a9244df0848122154315af71fe140f3db0fe014031783b0946b8c9d2e3;
    /// @dev value is equal to keccak256("OPERATOR_ROLE")
    bytes32 public constant OPERATOR_ROLE =
        0x97667070c54ef182b0f5858b034beac1b6f3089aa2d3188bb1e8929f4fa9b929;

    uint256 private constant __RANDOM_BIT = 0xffffffffffffffff;
    uint256 private constant __CUP_MASK = 0xccccccccccccccc; // 5%
    uint256 private constant __MASCOT_MASK = 0x1999999999999999; // 5%
    uint256 private constant __QATAR_MASK = 0x4ccccccccccccccc; // 20%
    uint256 private constant __SHOE_MASK = 0x7fffffffffffffff; // 20%

    /// @dev value is equal to keccak256("Permit(address user,uint256 userSeed,bytes32 houseSeed,uint256 deadline,uint256 nonce)")
    bytes32 private constant __PERMIT_TYPE_HASH =
        0xc02a18540b1f8010e03e4c5817e47f97371234f484e9bfa5b8d7423d54fad488;

    address public signer;
    bytes32 public root;
    uint256 public cost;
    uint256 public globalNonces;
    uint256 public tokenIdTracker;

    string public baseTokenURI;
    string public baseExtension;

    mapping(address => uint256) public signingNonces;
    mapping(address => CommitInfo) public commitments;
    mapping(uint8 => uint64[]) public attributePercentageMask;

    function initialize(
        string calldata name_,
        string calldata symbol_,
        string calldata baseTokenURI_, //
        string calldata baseExtension_ // json
    ) external initializer {
        __UUPSUpgradeable_init_unchained();
        __EIP712_init_unchained(name_, "1");

        baseTokenURI = baseTokenURI_;
        baseExtension = baseExtension_;
        __ERC721PresetMinterPauserAutoId_init(name_, symbol_, "");

        address sender = _msgSender();

        _grantRole(UPGRADER_ROLE, sender);
        _grantRole(OPERATOR_ROLE, sender);
        _grantRole(DEFAULT_ADMIN_ROLE, sender);
    }

    function setSigner(address signer_) external onlyRole(OPERATOR_ROLE) {
        emit NewSigner(_msgSender(), signer, signer_);
        signer = signer_;
    }

    function commit(bytes32 commitment_) external {
        address user = _msgSender();
        CommitInfo memory commitInfo;
        unchecked {
            commitInfo = CommitInfo({
                commitment: commitment_,
                blockNumberStart: block.number + 1,
                blockNumberEnd: block.number + 40
            });
        }

        emit Commited(
            user,
            commitInfo.blockNumberStart,
            commitInfo.blockNumberEnd,
            commitment_
        );

        commitments[user] = commitInfo;
    }

    function mintRandom(
        uint256 userSeed_,
        bytes32 houseSeed_,
        uint256 deadline_,
        bytes calldata signature_
    ) external {
        address user = _msgSender();
        if (block.timestamp > deadline_) revert ERC721R__Expired();

        CommitInfo memory commitInfo = commitments[user];
        if (
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        __PERMIT_TYPE_HASH,
                        user,
                        userSeed_,
                        houseSeed_,
                        deadline_,
                        ++signingNonces[user]
                    )
                )
            ).recover(signature_) != signer
        ) revert ERC721R__InvalidSignature();

        __mintRandom(commitInfo, user, userSeed_, houseSeed_);
    }

    function mintRandom(
        uint256 userSeed_,
        bytes32 houseSeed_,
        bytes32[] calldata proofs_
    ) external {
        if (!proofs_.verify(root, houseSeed_))
            revert ERC721R__InvalidHouseSeed();

        address user = _msgSender();
        __mintRandom(commitments[user], user, userSeed_, houseSeed_);
    }

    function metadataOf(
        uint256 tokenId_
    ) public view returns (uint256 rarity_, uint256 attributeId_) {
        if (ownerOf(tokenId_) == address(0)) revert ERC721R__TokenIdUnexisted();
        unchecked {
            rarity_ = tokenId_ & ((1 << 3) - 1);
            attributeId_ = (tokenId_ >> 3) & ((1 << 3) - 1);
        }
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        if (!_exists(tokenId)) revert ERC721R__TokenIdUnexisted();

        string memory currentBaseURI = baseTokenURI;
        (uint256 rarity, uint256 attributeId) = metadataOf(tokenId);
        return
            bytes(currentBaseURI).length > 0
                ? string(
                    abi.encodePacked(
                        currentBaseURI,
                        "/",
                        rarity.toString(),
                        "/",
                        attributeId.toString(),
                        baseExtension
                    )
                )
                : "";
    }

    function attributePercentMask(
        uint8 rarity_
    ) external view returns (uint64[] memory) {
        return attributePercentageMask[rarity_];
    }

    function updateAttributePercentMask(
        uint256 rarity_,
        uint64[] calldata percentageMask_
    ) external onlyRole(OPERATOR_ROLE) {
        attributePercentageMask[uint8(rarity_)] = percentageMask_;

        emit AttributePercentageMaskUpdated(
            _msgSender(),
            rarity_,
            percentageMask_
        );
    }

    function setRoot(bytes32 root_) external onlyRole(OPERATOR_ROLE) {
        emit NewRoot(_msgSender(), root, root_);
        root = root_;
    }

    function setCost(uint256 newCost_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit NewCost(_msgSender(), cost, newCost_);
        cost = newCost_;
    }

    function setBaseURI(
        string calldata newBaseURI_
    ) external onlyRole(OPERATOR_ROLE) {
        baseTokenURI = newBaseURI_;
        emit NewBaseURI(_msgSender(), newBaseURI_);
    }

    function setBaseExtension(
        string calldata extension_
    ) external onlyRole(OPERATOR_ROLE) {
        baseExtension = extension_;
        emit NewBaseExtension(_msgSender(), extension_);
    }

    function __mintRandom(
        CommitInfo memory commitInfo_,
        address user,
        uint256 userSeed_,
        bytes32 houseSeed_
    ) private {
        uint256 revealBlock;
        unchecked {
            revealBlock =
                commitInfo_.blockNumberStart +
                ((commitInfo_.blockNumberEnd - commitInfo_.blockNumberStart) >>
                    2);
        }
        assert(blockhash(revealBlock) != 0);

        if (block.number < revealBlock)
            revert ERC721R__RevealPhaseNotYetStarted();
        if (block.number > commitInfo_.blockNumberEnd)
            revert ERC721R__RevealPhaseExpired();
        if (
            keccak256(abi.encode(houseSeed_, userSeed_, user)) !=
            commitInfo_.commitment
        ) revert ERC721R__InvalidReveal();
        delete commitments[user];

        uint256 seed;
        unchecked {
            seed = uint256(
                keccak256(
                    abi.encode(
                        user,
                        ++globalNonces,
                        userSeed_,
                        houseSeed_,
                        address(this),
                        blockhash(revealBlock),
                        blockhash(block.number - 1),
                        blockhash(block.number - 2)
                    )
                )
            );
        }

        seed >>= 96;
        uint256 randomBit = __RANDOM_BIT;
        seed &= randomBit;

        uint256 rarity;
        if (seed < __CUP_MASK) rarity = uint256(Rarity.CUP);
        if (seed < __MASCOT_MASK) rarity = uint256(Rarity.MASCOT);
        if (seed < __QATAR_MASK) rarity = uint256(Rarity.QATAR);
        if (seed < __SHOE_MASK) rarity = uint256(Rarity.SHOE);
        else rarity = uint256(Rarity.BALL);

        seed = uint256(keccak256(abi.encode(seed ^ block.timestamp, user)));
        seed >>= 96;
        seed &= randomBit;

        uint256 attributeId;
        uint64[] memory percentageMask = attributePercentageMask[uint8(rarity)];
        uint256 length = percentageMask.length;
        for (uint256 i; i < length; ) {
            if (seed < percentageMask[i]) {
                attributeId = i;
                break;
            }
            unchecked {
                ++i;
            }
        }
        uint256 tokenId;
        unchecked {
            tokenId = (++tokenIdTracker << 6) | (attributeId << 3) | rarity;
        }

        _mint(user, tokenId);

        emit Unboxed(user, tokenId, rarity, attributeId);
    }

    function withdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
        address sender = _msgSender();
        uint256 balance = address(this).balance;
        (bool ok, ) = sender.call{value: balance}("");
        if (!ok) revert ERC721R__TransferFailed();

        emit Withdrawn(sender, balance);
    }

    function _authorizeUpgrade(
        address newImplementation_
    ) internal override onlyRole(UPGRADER_ROLE) {}

    uint256[40] private __gap;
}
