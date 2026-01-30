// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MaritimeRegistryAAOwner is Ownable {
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
    event BunkerFinalized(
        bytes32 indexed deliveryId, string imo, uint256 quantity, bytes sigSupplier, bytes sigChiefEng
    );
    event QuantumSealAnchored(bytes32 indexed deliveryId, string pdfHash);

    constructor() Ownable(msg.sender) {}

    //done
    function registerShip(string calldata _imo, address _chiefEng) external onlyOwner {
        shipToChiefEng[_imo] = _chiefEng;
    }

    //done
    function registerSupplier(uint256 _supplierId, address _barge) external onlyOwner {
        supplierToBarge[_supplierId] = _barge;
    }

    //done
    function nominateBunker(bytes32 _deliveryId, string calldata _imo, uint256 _supplierId, uint256 _expectedSulphur)
        external
        onlyOwner
    {
        require(bunkerNotes[_deliveryId].status == BunkerStatus.None, "Delivery ID exists");

        bunkerNotes[_deliveryId].imoNumber = _imo;
        bunkerNotes[_deliveryId].supplierId = _supplierId;
        bunkerNotes[_deliveryId].sulphurContent = _expectedSulphur;
        bunkerNotes[_deliveryId].status = BunkerStatus.Nominated;

        emit BunkerNominated(_deliveryId, _imo, _supplierId);
    }

    //done
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

        // ['bytes32', 'string', 'uint256', 'uint256', 'uint256', 'uint256', 'string'],
        // [delivery_id, imo_number, supplier_id, density, expected_sulphur, qty, sample_id]

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

        address recoveredSupplier = messageHash.recover(_sigSupplier);
        address recoveredChief = messageHash.recover(_sigChiefEng);

        require(recoveredSupplier == supplierToBarge[note.supplierId], "Invalid Supplier Signature");
        require(recoveredChief == shipToChiefEng[note.imoNumber], "Invalid Chief Engineer Signature");

        note.densityAt15C = _finalDensity;
        note.quantityMT = _finalQty;
        note.sampleId = _sampleId;
        note.signatureSupplier = _sigSupplier;
        note.signatureChiefEng = _sigChiefEng;
        note.timestamp = block.timestamp;
        note.status = BunkerStatus.Finalized;

        emit BunkerFinalized(_deliveryId, note.imoNumber, _finalQty, _sigSupplier, _sigChiefEng);
    }

    function anchorQuantumSeal(bytes32 _deliveryId, string calldata _pdfHash, bytes calldata _quantumSig)
        external
        onlyOwner
    {
        BunkerNote storage note = bunkerNotes[_deliveryId];
        require(note.status == BunkerStatus.Finalized, "Bunker not finalized");

        note.pdfHash = _pdfHash;
        note.quantumSignature = _quantumSig;
        note.status = BunkerStatus.QuantumSealed;

        emit QuantumSealAnchored(_deliveryId, _pdfHash);
    }

    function getNote(bytes32 _deliveryId) external view returns (BunkerNote memory) {
        return bunkerNotes[_deliveryId];
    }

    function verifyStoredNote(bytes32 _deliveryId)
        external
        view
        returns (bool allSignaturesValid, string memory imoVerified, address recoveredChief, address recoveredBarge)
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

        address actualBarge = messageHash.recover(note.signatureSupplier);
        address actualChief = messageHash.recover(note.signatureChiefEng);

        bool supplierMatch = (actualBarge == supplierToBarge[note.supplierId]);
        bool shipMatch = (actualChief == shipToChiefEng[note.imoNumber]);

        return ((supplierMatch && shipMatch), note.imoNumber, actualChief, actualBarge);
    }
}
