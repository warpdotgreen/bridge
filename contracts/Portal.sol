// SPDX-License-Identifier: MIT License
/* yak tracks all over the place */

pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IPortalMessageReceiver.sol";

contract Portal is Initializable, OwnableUpgradeable {
    uint256 public ethNonce = 0;
    mapping(bytes32 => bool) private usedNonces;

    uint256 public messageToll;

    mapping(address => bool) public isSigner;
    uint256 public signatureThreshold;

    event MessageSent(
        bytes32 indexed nonce,
        address source,
        bytes3 destination_chain,
        bytes32 destination,
        bytes32[] contents
    );

    event MessageReceived(
        bytes32 indexed nonce,
        bytes3 source_chain,
        bytes32 source,
        address destination,
        bytes32[] contents
    );

    event SignerUpdated(address signer, bool isSigner);

    event SignagtureThresholdUpdated(uint256 newThreshold);

    event MessageTollUpdated(uint256 newFee);

    function initialize(
        address _coldMultisig,
        uint256 _messageToll,
        address[] calldata _signers,
        uint256 _signatureThreshold
    ) external initializer {
        __Ownable_init(_coldMultisig);

        messageToll = _messageToll;
        signatureThreshold = _signatureThreshold;

        for (uint256 i = 0; i < _signers.length; i++) {
            isSigner[_signers[i]] = true;
        }
    }

    receive() external payable {}

    function sendMessage(
        bytes3 _destination_chain,
        bytes32 _destination,
        bytes32[] calldata _contents
    ) external payable {
        require(msg.value == messageToll, "!toll");
        ethNonce += 1;

        (bool success, ) = block.coinbase.call{value: msg.value}(new bytes(0));
        require(success, "!toll");

        emit MessageSent(
            bytes32(ethNonce),
            msg.sender,
            _destination_chain,
            _destination,
            _contents
        );
    }

    function receiveMessage(
        bytes32 _nonce,
        bytes3 _source_chain,
        bytes32 _source,
        address _destination,
        bytes32[] calldata _contents,
        bytes memory _sigs
    ) external {
        require(_sigs.length == signatureThreshold * 65, "!len");

        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(
                    abi.encodePacked(
                        _nonce,
                        _source_chain,
                        _source,
                        _destination,
                        _contents
                    )
                )
            )
        );

        address lastSigner = address(0);

        for (uint256 i = 0; i < signatureThreshold; i++) {
            uint8 v;
            bytes32 r;
            bytes32 s;

            assembly {
                let ib := add(mul(65, i), 32)
                v := byte(0, mload(add(_sigs, ib)))
                r := mload(add(_sigs, add(1, ib)))
                s := mload(add(_sigs, add(33, ib)))
            }

            address signer = ecrecover(messageHash, v, r, s);
            require(isSigner[signer], "!signer");
            require(signer > lastSigner, "!order");
            lastSigner = signer;
        }

        bytes32 key = keccak256(abi.encodePacked(_source_chain, _nonce));
        require(!usedNonces[key], "!nonce");
        usedNonces[key] = true;

        IPortalMessageReceiver(_destination).receiveMessage(
            _nonce,
            _source_chain,
            _source,
            _contents
        );

        emit MessageReceived(
            _nonce,
            _source_chain,
            _source,
            _destination,
            _contents
        );
    }

    function rescueEther(
        address[] calldata _receivers,
        uint256[] calldata _amounts
    ) external onlyOwner {
        for (uint256 i = 0; i < _receivers.length; i++) {
            payable(_receivers[i]).transfer(_amounts[i]);
        }
    }

    function rescueAsset(
        address _assetContract,
        address[] calldata _receivers,
        uint256[] calldata _amounts
    ) external onlyOwner {
        for (uint256 i = 0; i < _receivers.length; i++) {
            SafeERC20.safeTransfer(
                IERC20(_assetContract),
                _receivers[i],
                _amounts[i]
            );
        }
    }

    function updateSigner(address _signer, bool _newValue) external onlyOwner {
        require(isSigner[_signer] != _newValue, "!diff");
        isSigner[_signer] = _newValue;

        emit SignerUpdated(_signer, _newValue);
    }

    function updateSignatureThreshold(uint256 _newValue) external onlyOwner {
        require(signatureThreshold != _newValue && _newValue > 0, "!val");
        signatureThreshold = _newValue;

        emit SignagtureThresholdUpdated(_newValue);
    }

    function updateMessageToll(uint256 _newValue) external onlyOwner {
        require(messageToll != _newValue, "!diff");
        messageToll = _newValue;

        emit MessageTollUpdated(_newValue);
    }
}
