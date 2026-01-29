// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IMinimalAccount {
    function owner() external view returns (address);
}

contract BunkerControl is Ownable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    enum BunkerStatus {
        None,
        Nominated,
        Finalized,
        QuantumSealed
    }

    struct BunkerNote {
        string imoNumber;
        uint256 supplierId;
        uint256 densityAt15C;
        uint256 sulphurContent;
        uint256 quantityMT;
        string sampleId;
        uint256 timestamp;
        BunkerStatus status;
        bytes signatureSupplier;
        bytes signatureChiefEng;
        string pdfHash;
        bytes quantumSignature;
    }

    mapping(string => address) public shipToChiefEng;
    mapping(uint256 => address) public supplierToBarge;

    mapping(bytes32 => BunkerNote) public bunkerNotes;

    event BunkerNominated(bytes32 indexed deliveryId, string imo, uint256 supplierId);
    event BunkerFinalized(bytes32 indexed deliveryId, string imo, uint256 quantity);
    event QuantumSealAnchored(bytes32 indexed deliveryId, string pdfHash);

    constructor() Ownable(msg.sender) {}

    function registerShip(string calldata _imo, address _chiefEngAccount) external onlyOwner {
        shipToChiefEng[_imo] = _chiefEngAccount;
    }

    function registerSupplier(uint256 _supplierId, address _bargeAccount) external onlyOwner {
        supplierToBarge[_supplierId] = _bargeAccount;
    }

    function nominateBunker(bytes32 _deliveryId, string calldata _imo, uint256 _supplierId, uint256 _expectedSulphur)
        external
    {
        require(msg.sender == supplierToBarge[_supplierId], "Only authorized barge account can nominate");
        require(bunkerNotes[_deliveryId].status == BunkerStatus.None, "Delivery ID exists");

        bunkerNotes[_deliveryId].imoNumber = _imo;
        bunkerNotes[_deliveryId].supplierId = _supplierId;
        bunkerNotes[_deliveryId].sulphurContent = _expectedSulphur;
        bunkerNotes[_deliveryId].status = BunkerStatus.Nominated;

        emit BunkerNominated(_deliveryId, _imo, _supplierId);
    }

    function finalizeBunker(
        bytes32 _deliveryId,
        uint256 _finalDensity,
        uint256 _finalQty,
        string calldata _sampleId,
        bytes calldata _sigSupplier,
        bytes calldata _sigChiefEng
    ) external onlyOwner {
        BunkerNote storage note = bunkerNotes[_deliveryId];
        require(note.status == BunkerStatus.Nominated, "Bunker not nominated");

        bytes32 messageHash = keccak256(
                abi.encode(
                    _deliveryId,
                    note.imoNumber,
                    note.supplierId,
                    _finalDensity,
                    note.sulphurContent,
                    _finalQty,
                    _sampleId
                )
            ).toEthSignedMessageHash();

        address recoveredSupplierSigner = messageHash.recover(_sigSupplier);
        address recoveredChiefSigner = messageHash.recover(_sigChiefEng);

        address bargeAA = supplierToBarge[note.supplierId];
        address shipAA = shipToChiefEng[note.imoNumber];

        //verify with the minimal account owner
        require(recoveredSupplierSigner == IMinimalAccount(bargeAA).owner(), "Invalid Supplier Owner Signature");
        require(recoveredChiefSigner == IMinimalAccount(shipAA).owner(), "Invalid Chief Engineer Owner Signature");

        note.densityAt15C = _finalDensity;
        note.quantityMT = _finalQty;
        note.sampleId = _sampleId;
        note.signatureSupplier = _sigSupplier;
        note.signatureChiefEng = _sigChiefEng;
        note.timestamp = block.timestamp;
        note.status = BunkerStatus.Finalized;

        emit BunkerFinalized(_deliveryId, note.imoNumber, _finalQty);
    }

    function verifyStoredNote(bytes32 _deliveryId)
        external
        view
        returns (
            bool allSignaturesValid,
            string memory imoVerified,
            address recoveredChiefOwner,
            address recoveredBargeOwner
        )
    {
        BunkerNote storage note = bunkerNotes[_deliveryId];
        require(note.status >= BunkerStatus.Finalized, "Bunker note not finalized");

        bytes32 messageHash = keccak256(
                abi.encode(
                    _deliveryId,
                    note.imoNumber,
                    note.supplierId,
                    note.densityAt15C,
                    note.sulphurContent,
                    note.quantityMT,
                    note.sampleId
                )
            ).toEthSignedMessageHash();

        address actualBargeOwner = messageHash.recover(note.signatureSupplier);
        address actualChiefOwner = messageHash.recover(note.signatureChiefEng);

        bool supplierMatch = (actualBargeOwner == IMinimalAccount(supplierToBarge[note.supplierId]).owner());
        bool shipMatch = (actualChiefOwner == IMinimalAccount(shipToChiefEng[note.imoNumber]).owner());

        return ((supplierMatch && shipMatch), note.imoNumber, actualChiefOwner, actualBargeOwner);
    }

    function getNote(bytes32 _deliveryId) external view returns (BunkerNote memory) {
        return bunkerNotes[_deliveryId];
    }
}
