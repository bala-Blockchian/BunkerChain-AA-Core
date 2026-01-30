// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console, Vm} from "forge-std/Test.sol";
import {MaritimeRegistryAAOwner} from "../src/MaritimeRegistryAAOwner.sol";
import {MinimalAccount} from "../src/MinimalAccount.sol";
import {DeployMinimal} from "../script/DeployMinimal.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {EntryPoint} from "lib/account-abstraction/contracts/core/EntryPoint.sol";
import {SendPackedUserOp, PackedUserOperation, IEntryPoint} from "script/SendPackedUserOp.s.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract MaritimeRegistryAAOwnerTest is Test {
    MaritimeRegistryAAOwner public registry;
    SendPackedUserOp public sendPackedUserOp;

    MinimalAccount public minimalAccount;
    HelperConfig public helperConfig;

    Vm.Wallet public chiefWallet;
    Vm.Wallet public bunkerWallet;

    string constant IMO_NUMBER = "IMO_GOLDEN_HIND";
    uint256 constant SUPPLIER_ID = 888;

    function setUp() public {
        DeployMinimal deployMinimal = new DeployMinimal();
        (helperConfig, minimalAccount) = deployMinimal.deployMinimalAccount();

        vm.prank(address(minimalAccount));
        registry = new MaritimeRegistryAAOwner();

        chiefWallet = vm.createWallet("chiefEngineer");
        bunkerWallet = vm.createWallet("bunkerTanker");

        vm.startPrank(address(minimalAccount));
        registry.registerShip(IMO_NUMBER, chiefWallet.addr);
        registry.registerSupplier(SUPPLIER_ID, bunkerWallet.addr);
        vm.stopPrank();

        sendPackedUserOp = new SendPackedUserOp();
    }

    function testRegistryOwnershipAndMappings() public view {
        assertEq(registry.owner(), address(minimalAccount));

        assertEq(registry.shipToChiefEng(IMO_NUMBER), chiefWallet.addr);
        assertEq(registry.supplierToBarge(SUPPLIER_ID), bunkerWallet.addr);

        console.log("Registry Owner (AA):", registry.owner());
        console.log("Chief Engineer Registered:", chiefWallet.addr);
        console.log("Bunker Supplier Registered:", bunkerWallet.addr);
    }

    function testNominateBunkerUpdatesStatus() public {
        bytes32 deliveryId = keccak256("DELIVERY_001");
        uint256 expectedSulphur = 500;

        vm.startPrank(address(minimalAccount));
        registry.nominateBunker(deliveryId, IMO_NUMBER, SUPPLIER_ID, expectedSulphur);
        vm.stopPrank();

        MaritimeRegistryAAOwner.BunkerNote memory note = registry.getNote(deliveryId);

        assertEq(
            uint256(note.status), uint256(MaritimeRegistryAAOwner.BunkerStatus.Nominated), "Status should be Nominated"
        );

        assertEq(note.imoNumber, IMO_NUMBER, "IMO Number mismatch");
        assertEq(note.supplierId, SUPPLIER_ID, "Supplier ID mismatch");
        assertEq(note.sulphurContent, expectedSulphur, "Sulphur content mismatch");
    }

    function testOwnerCanExecuteNomination() public {
        bytes32 deliveryId = keccak256("DELIVERY_002");
        uint256 expectedSulphur = 500;

        bytes memory nominateData = abi.encodeWithSelector(
            MaritimeRegistryAAOwner.nominateBunker.selector, deliveryId, IMO_NUMBER, SUPPLIER_ID, expectedSulphur
        );

        vm.prank(minimalAccount.owner());
        minimalAccount.execute(address(registry), 0, nominateData);

        MaritimeRegistryAAOwner.BunkerNote memory note = registry.getNote(deliveryId);

        assertEq(
            uint256(note.status), uint256(MaritimeRegistryAAOwner.BunkerStatus.Nominated), "Status should be Nominated"
        );
        assertEq(note.imoNumber, IMO_NUMBER, "IMO mismatch");
        assertEq(note.supplierId, SUPPLIER_ID, "Supplier ID mismatch");
        assertEq(note.sulphurContent, expectedSulphur, "Sulphur mismatch");
    }

    function testRandomUserCannotExecute() public {
        address randomUser = makeAddr("randomUser");
        bytes32 deliveryId = keccak256("DELIVERY_002");
        uint256 expectedSulphur = 500;

        bytes memory nominateData = abi.encodeWithSelector(
            MaritimeRegistryAAOwner.nominateBunker.selector, deliveryId, IMO_NUMBER, SUPPLIER_ID, expectedSulphur
        );

        vm.prank(randomUser);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        minimalAccount.execute(address(registry), 0, nominateData);
    }

    function testUserOpSignatureVerification() public {
        bytes32 deliveryId = keccak256("DELIVERY_AA_001");
        uint256 expectedSulphur = 500;

        bytes memory nominateData = abi.encodeWithSelector(
            MaritimeRegistryAAOwner.nominateBunker.selector, deliveryId, IMO_NUMBER, SUPPLIER_ID, expectedSulphur
        );
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, address(registry), 0, nominateData);

        PackedUserOperation memory packedUserOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );

        bytes32 userOperationHash = IEntryPoint(helperConfig.getConfig().entryPoint).getUserOpHash(packedUserOp);
        address actualSigner =
            ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(userOperationHash), packedUserOp.signature);

        assertEq(actualSigner, minimalAccount.owner(), "Signature should be from account owner");
        console.log("Signature Verified! UserOp for Maritime Registry signed by:", actualSigner);
    }

    function testValidateUserOp() public {
        bytes32 deliveryId = keccak256("DELIVERY_VAL_001");
        uint256 expectedSulphur = 500;

        bytes memory nominateData = abi.encodeWithSelector(
            MaritimeRegistryAAOwner.nominateBunker.selector, deliveryId, IMO_NUMBER, SUPPLIER_ID, expectedSulphur
        );

        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, address(registry), 0, nominateData);

        PackedUserOperation memory packedUserOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );

        address entryPoint = helperConfig.getConfig().entryPoint;
        bytes32 userOperationHash = IEntryPoint(entryPoint).getUserOpHash(packedUserOp);

        uint256 missingAccountFunds = 1 ether;
        vm.deal(address(minimalAccount), 2 ether);

        vm.prank(entryPoint);
        uint256 validationData = minimalAccount.validateUserOp(packedUserOp, userOperationHash, missingAccountFunds);

        assertEq(validationData, 0, "Validation should return 0 (success)");
        assertEq(entryPoint.balance, missingAccountFunds, "EntryPoint should receive the pre-fund");
    }

    function testEntryPointCanExecuteNomination() public {
        bytes32 deliveryId = keccak256("DELIVERY_FULL_FLOW_001");
        uint256 expectedSulphur = 500;

        address entryPointAddress = helperConfig.getConfig().entryPoint;
        address randomUser = makeAddr("bundler");

        bytes memory nominateData = abi.encodeWithSelector(
            MaritimeRegistryAAOwner.nominateBunker.selector, deliveryId, IMO_NUMBER, SUPPLIER_ID, expectedSulphur
        );

        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, address(registry), 0, nominateData);

        PackedUserOperation memory packedUserOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );

        vm.deal(address(minimalAccount), 1 ether);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOp;

        vm.prank(randomUser);
        IEntryPoint(entryPointAddress).handleOps(ops, payable(randomUser));

        MaritimeRegistryAAOwner.BunkerNote memory note = registry.getNote(deliveryId);

        assertEq(
            uint256(note.status),
            uint256(MaritimeRegistryAAOwner.BunkerStatus.Nominated),
            "Note should be in Nominated status"
        );
        assertEq(note.imoNumber, IMO_NUMBER, "IMO mismatch");
        assertEq(note.supplierId, SUPPLIER_ID, "Supplier mismatch");
        assertEq(note.sulphurContent, expectedSulphur, "Sulphur mismatch");

        console.log("Nomination successfully processed via AA EntryPoint!");
    }

    //internal helper
    function executeNominationViaEntryPoint(bytes32 deliveryId, uint256 expectedSulphur) internal {
        address entryPointAddress = helperConfig.getConfig().entryPoint;
        address bundler = makeAddr("bundler");

        bytes memory nominateData = abi.encodeWithSelector(
            MaritimeRegistryAAOwner.nominateBunker.selector, deliveryId, IMO_NUMBER, SUPPLIER_ID, expectedSulphur
        );

        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, address(registry), 0, nominateData);
        PackedUserOperation memory packedUserOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );

        vm.deal(address(minimalAccount), 1 ether);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOp;

        vm.prank(bundler);
        IEntryPoint(entryPointAddress).handleOps(ops, payable(bundler));
    }

    modifier nominatedViaAA(bytes32 deliveryId, uint256 expectedSulphur) {
        address entryPointAddress = helperConfig.getConfig().entryPoint;
        address bundler = makeAddr("bundler");

        bytes memory nominateData = abi.encodeWithSelector(
            MaritimeRegistryAAOwner.nominateBunker.selector, deliveryId, IMO_NUMBER, SUPPLIER_ID, expectedSulphur
        );

        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, address(registry), 0, nominateData);
        PackedUserOperation memory packedUserOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );

        vm.deal(address(minimalAccount), 1 ether);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOp;

        vm.prank(bundler);
        IEntryPoint(entryPointAddress).handleOps(ops, payable(bundler));
        _;
    }

    modifier finalizedViaAA(bytes32 deliveryId, uint256 expectedSulphur) {
        uint256 finalDensity = 991;
        uint256 finalQty = 1200;
        string memory sampleId = "SAMPLE_XYZ_99";

        bytes32 structHash = keccak256(
            abi.encode(deliveryId, IMO_NUMBER, SUPPLIER_ID, finalDensity, expectedSulphur, finalQty, sampleId)
        );
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(structHash);

        (uint8 vS, bytes32 rS, bytes32 sS) = vm.sign(bunkerWallet.privateKey, digest);
        bytes memory sigSupplier = abi.encodePacked(rS, sS, vS);

        (uint8 vC, bytes32 rC, bytes32 sC) = vm.sign(chiefWallet.privateKey, digest);
        bytes memory sigChief = abi.encodePacked(rC, sC, vC);

        bytes memory finalizeData = abi.encodeWithSelector(
            MaritimeRegistryAAOwner.finalizeBunker.selector,
            deliveryId,
            finalDensity,
            finalQty,
            sampleId,
            sigSupplier,
            sigChief
        );

        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, address(registry), 0, finalizeData);

        PackedUserOperation memory packedUserOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );

        vm.deal(address(minimalAccount), 1 ether);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOp;

        address entryPointAddress = helperConfig.getConfig().entryPoint;
        address bundler = makeAddr("bundler");

        vm.prank(bundler);
        IEntryPoint(entryPointAddress).handleOps(ops, payable(bundler));

        _;
    }

    function testFinalizeBunker() public {
        bytes32 deliveryId = keccak256("DELIVERY_FINAL_001");
        uint256 expectedSulphur = 500;

        executeNominationViaEntryPoint(deliveryId, expectedSulphur);

        uint256 finalDensity = 991;
        uint256 finalQty = 1200;
        string memory sampleId = "SAMPLE_XYZ_99";

        bytes32 structHash = keccak256(
            abi.encode(deliveryId, IMO_NUMBER, SUPPLIER_ID, finalDensity, expectedSulphur, finalQty, sampleId)
        );
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(structHash);

        (uint8 vS, bytes32 rS, bytes32 sS) = vm.sign(bunkerWallet.privateKey, digest);
        bytes memory sigSupplier = abi.encodePacked(rS, sS, vS);

        (uint8 vC, bytes32 rC, bytes32 sC) = vm.sign(chiefWallet.privateKey, digest);
        bytes memory sigChief = abi.encodePacked(rC, sC, vC);

        vm.expectEmit(true, false, false, true);
        emit MaritimeRegistryAAOwner.BunkerFinalized(deliveryId, IMO_NUMBER, finalQty, sigSupplier, sigChief);

        vm.prank(address(minimalAccount));
        registry.finalizeBunker(deliveryId, finalDensity, finalQty, sampleId, sigSupplier, sigChief);

        MaritimeRegistryAAOwner.BunkerNote memory note = registry.getNote(deliveryId);

        assertEq(uint256(note.status), uint256(MaritimeRegistryAAOwner.BunkerStatus.Finalized));
        assertEq(note.densityAt15C, finalDensity);
        assertEq(note.quantityMT, finalQty);
        assertEq(note.sampleId, sampleId);
        assertEq(note.signatureSupplier, sigSupplier);
        assertEq(note.signatureChiefEng, sigChief);
        assertTrue(note.timestamp > 0);

        assertEq(note.imoNumber, IMO_NUMBER, "IMO mismatch");
        assertEq(note.supplierId, SUPPLIER_ID, "Supplier ID mismatch");
        assertEq(note.sulphurContent, expectedSulphur, "Sulphur mismatch");
    }

    function testFinalizeBunkerViaAA() public {
        bytes32 deliveryId = keccak256("DELIVERY_FINAL_001");
        uint256 expectedSulphur = 500;

        executeNominationViaEntryPoint(deliveryId, expectedSulphur);

        uint256 finalDensity = 991;
        uint256 finalQty = 1200;
        string memory sampleId = "SAMPLE_XYZ_99";

        bytes32 structHash = keccak256(
            abi.encode(deliveryId, IMO_NUMBER, SUPPLIER_ID, finalDensity, expectedSulphur, finalQty, sampleId)
        );
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(structHash);

        (uint8 vS, bytes32 rS, bytes32 sS) = vm.sign(bunkerWallet.privateKey, digest);
        bytes memory sigSupplier = abi.encodePacked(rS, sS, vS);

        (uint8 vC, bytes32 rC, bytes32 sC) = vm.sign(chiefWallet.privateKey, digest);
        bytes memory sigChief = abi.encodePacked(rC, sC, vC);

        bytes memory finalizeData = abi.encodeWithSelector(
            MaritimeRegistryAAOwner.finalizeBunker.selector,
            deliveryId,
            finalDensity,
            finalQty,
            sampleId,
            sigSupplier,
            sigChief
        );

        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, address(registry), 0, finalizeData);

        PackedUserOperation memory packedUserOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );

        vm.deal(address(minimalAccount), 1 ether);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOp;

        address entryPointAddress = helperConfig.getConfig().entryPoint;
        address bundler = makeAddr("bundler");

        vm.expectEmit(true, false, false, true);
        emit MaritimeRegistryAAOwner.BunkerFinalized(deliveryId, IMO_NUMBER, finalQty, sigSupplier, sigChief);

        vm.prank(bundler);
        IEntryPoint(entryPointAddress).handleOps(ops, payable(bundler));

        MaritimeRegistryAAOwner.BunkerNote memory note = registry.getNote(deliveryId);

        assertEq(uint256(note.status), uint256(MaritimeRegistryAAOwner.BunkerStatus.Finalized));
        assertEq(note.densityAt15C, finalDensity);
        assertEq(note.quantityMT, finalQty);
        assertEq(note.sampleId, sampleId);
        assertEq(note.signatureSupplier, sigSupplier);
        assertEq(note.signatureChiefEng, sigChief);
        assertTrue(note.timestamp > 0);

        assertEq(note.imoNumber, IMO_NUMBER, "IMO mismatch");
        assertEq(note.supplierId, SUPPLIER_ID, "Supplier ID mismatch");
        assertEq(note.sulphurContent, expectedSulphur, "Sulphur mismatch");
    }

    function testFinalizeBunkerViaAAMod() public nominatedViaAA(keccak256("DELIVERY_FINAL_001"), 500) {
        bytes32 deliveryId = keccak256("DELIVERY_FINAL_001");
        uint256 expectedSulphur = 500;
        uint256 finalDensity = 991;
        uint256 finalQty = 1200;
        string memory sampleId = "SAMPLE_XYZ_99";

        bytes32 structHash = keccak256(
            abi.encode(deliveryId, IMO_NUMBER, SUPPLIER_ID, finalDensity, expectedSulphur, finalQty, sampleId)
        );
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(structHash);

        (uint8 vS, bytes32 rS, bytes32 sS) = vm.sign(bunkerWallet.privateKey, digest);
        bytes memory sigSupplier = abi.encodePacked(rS, sS, vS);

        (uint8 vC, bytes32 rC, bytes32 sC) = vm.sign(chiefWallet.privateKey, digest);
        bytes memory sigChief = abi.encodePacked(rC, sC, vC);

        bytes memory finalizeData = abi.encodeWithSelector(
            MaritimeRegistryAAOwner.finalizeBunker.selector,
            deliveryId,
            finalDensity,
            finalQty,
            sampleId,
            sigSupplier,
            sigChief
        );

        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, address(registry), 0, finalizeData);

        PackedUserOperation memory packedUserOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );

        vm.deal(address(minimalAccount), 1 ether);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOp;

        address entryPointAddress = helperConfig.getConfig().entryPoint;
        address bundler = makeAddr("bundler");

        vm.expectEmit(true, false, false, true);
        emit MaritimeRegistryAAOwner.BunkerFinalized(deliveryId, IMO_NUMBER, finalQty, sigSupplier, sigChief);

        vm.prank(bundler);
        IEntryPoint(entryPointAddress).handleOps(ops, payable(bundler));

        MaritimeRegistryAAOwner.BunkerNote memory note = registry.getNote(deliveryId);

        assertEq(uint256(note.status), uint256(MaritimeRegistryAAOwner.BunkerStatus.Finalized));
        assertEq(note.densityAt15C, finalDensity);
        assertEq(note.quantityMT, finalQty);
        assertEq(note.sampleId, sampleId);
        assertEq(note.signatureSupplier, sigSupplier);
        assertEq(note.signatureChiefEng, sigChief);
        assertTrue(note.timestamp > 0);

        assertEq(note.imoNumber, IMO_NUMBER, "IMO mismatch");
        assertEq(note.supplierId, SUPPLIER_ID, "Supplier ID mismatch");
        assertEq(note.sulphurContent, expectedSulphur, "Sulphur mismatch");
    }

    //testing the verifyStoredNote function with both the modifier
    function testVerifyStoredNoteSignatures()
        public
        nominatedViaAA(keccak256("FULL_FLOW"), 500)
        finalizedViaAA(keccak256("FULL_FLOW"), 500)
    {
        bytes32 deliveryId = keccak256("FULL_FLOW");

        (bool allSignaturesValid, string memory imoVerified, address recoveredChief, address recoveredBarge) =
            registry.verifyStoredNote(deliveryId);

        assertTrue(allSignaturesValid, "Signatures should be cryptographically valid");
        assertEq(imoVerified, IMO_NUMBER, "IMO number mismatch in verification");

        assertEq(recoveredChief, chiefWallet.addr, "Recovered Chief Engineer address mismatch");
        assertEq(recoveredBarge, bunkerWallet.addr, "Recovered Barge address mismatch");

        MaritimeRegistryAAOwner.BunkerNote memory note = registry.getNote(deliveryId);
        assertEq(uint256(note.status), uint256(MaritimeRegistryAAOwner.BunkerStatus.Finalized));

        console.log("Verification Successful for IMO:", imoVerified);
        console.log("Recovered Chief:", recoveredChief);
        console.log("Recovered Barge:", recoveredBarge);
    }

    //tested the anchorQuantumSeal function with AA
    function testAnchorQuantumSealViaAA()
        public
        nominatedViaAA(keccak256("FULL_FLOW"), 500)
        finalizedViaAA(keccak256("FULL_FLOW"), 500)
    {
        bytes32 deliveryId = keccak256("FULL_FLOW");
        string memory pdfHash = "QmQuantumPDFHash123456789";
        bytes memory quantumSig = abi.encodePacked("QUANTUM_SECURITY_PROOFS");

        bytes memory quantumData =
            abi.encodeWithSelector(MaritimeRegistryAAOwner.anchorQuantumSeal.selector, deliveryId, pdfHash, quantumSig);

        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, address(registry), 0, quantumData);

        PackedUserOperation memory packedUserOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );

        vm.deal(address(minimalAccount), 1 ether);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOp;

        address entryPointAddress = helperConfig.getConfig().entryPoint;
        address bundler = makeAddr("bundler");

        vm.expectEmit(true, false, false, true);
        emit MaritimeRegistryAAOwner.QuantumSealAnchored(deliveryId, pdfHash);

        vm.prank(bundler);
        IEntryPoint(entryPointAddress).handleOps(ops, payable(bundler));

        MaritimeRegistryAAOwner.BunkerNote memory note = registry.getNote(deliveryId);

        assertEq(
            uint256(note.status),
            uint256(MaritimeRegistryAAOwner.BunkerStatus.QuantumSealed),
            "Status should be QuantumSealed"
        );
        assertEq(note.pdfHash, pdfHash, "PDF Hash mismatch");
        assertEq(note.quantumSignature, quantumSig, "Quantum Signature mismatch");

        console.log("Final State Reached: QuantumSealed");
        console.log("PDF Hash Anchored:", note.pdfHash);
    }

    //test case to check tranferownership
    function testTransferOwnershipViaEntryPoint() public {
        address newOwner = makeAddr("newOwner");

        address entryPointAddress = helperConfig.getConfig().entryPoint;
        address bundler = makeAddr("bundler");

        bytes memory transferData =
            abi.encodeWithSelector(MinimalAccount.transferOwnershipFromEntryPoint.selector, newOwner);

        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, address(minimalAccount), 0, transferData);

        PackedUserOperation memory packedUserOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );

        vm.deal(address(minimalAccount), 1 ether);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOp;

        vm.prank(bundler);
        IEntryPoint(entryPointAddress).handleOps(ops, payable(bundler));

        assertEq(minimalAccount.owner(), newOwner, "Ownership should be transferred to newOwner");
    }

    function testOldOwnerCannotNominateAfterTransfer() public {
        address newOwner = makeAddr("newOwner");

        address entryPointAddress = helperConfig.getConfig().entryPoint;
        address bundler = makeAddr("bundler");

        bytes memory transferData =
            abi.encodeWithSelector(MinimalAccount.transferOwnershipFromEntryPoint.selector, newOwner);

        bytes memory executeTransferCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, address(minimalAccount), 0, transferData);

        PackedUserOperation memory transferOp = sendPackedUserOp.generateSignedUserOperation(
            executeTransferCallData, helperConfig.getConfig(), address(minimalAccount)
        );

        vm.deal(address(minimalAccount), 1 ether);
        PackedUserOperation[] memory transferOps = new PackedUserOperation[](1);
        transferOps[0] = transferOp;

        vm.prank(bundler);
        IEntryPoint(entryPointAddress).handleOps(transferOps, payable(bundler));

        assertEq(minimalAccount.owner(), newOwner);

        bytes32 deliveryId = keccak256("STOLEN_DELIVERY");
        bytes memory nominateData = abi.encodeWithSelector(
            MaritimeRegistryAAOwner.nominateBunker.selector, deliveryId, IMO_NUMBER, SUPPLIER_ID, 500
        );

        bytes memory executeNominateCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, address(registry), 0, nominateData);

        PackedUserOperation memory invalidOp = sendPackedUserOp.generateSignedUserOperation(
            executeNominateCallData, helperConfig.getConfig(), address(minimalAccount)
        );

        PackedUserOperation[] memory invalidOps = new PackedUserOperation[](1);
        invalidOps[0] = invalidOp;

        vm.prank(bundler);

        // In ERC-4337, if validation fails, handleOps reverts with a FailedOp error
        vm.expectRevert();
        IEntryPoint(entryPointAddress).handleOps(invalidOps, payable(bundler));

        assertEq(uint256(registry.getNote(deliveryId).status), 0);
    }

    //inside the read me alson include the flow
    //i have craetd the image for this flow also add the image

    //owner of the AA signs the userop tx
    // random node in the alt mempool sends this tx to blockchain
    //call the enrtypoint
    //entrypoint then calls the minimal account(AA - contract account)
    //AA - contract Account verifier the signature from the owner using the userop tx object
    //AA - contract Account executes the call from the userop tx object
    //this executue function calls the maritime registry contract
    //which verifies the signature fo both the burnker and the chief signature on chain using ECDSA

    //also mention included a novel functionality ins the  aAA conrtact
    // the admin of the maritime registry contract can tranfer the ownership in a sercred manner withut reveling the
    // private key usin the AA userops tx
    // icnluded the test for all the features of the smart contract
}
