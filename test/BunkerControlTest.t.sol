// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console, Vm} from "forge-std/Test.sol";
import {BunkerControl} from "../src/BunkerControl.sol";
import {MinimalAccount} from "../src/MinimalAccount.sol";
import {EntryPoint} from "lib/account-abstraction/contracts/core/EntryPoint.sol";
import {SendPackedUserOp, PackedUserOperation, IEntryPoint} from "script/SendPackedUserOp.s.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract BunkerControlTest is Test {
    BunkerControl public registry;

    MinimalAccount public bargeAA;
    MinimalAccount public chiefAA;

    EntryPoint public entryPointBarge;
    EntryPoint public entryPointChief;

    Vm.Wallet public bargeOwner;
    Vm.Wallet public chiefOwner;

    SendPackedUserOp public sendPackedUserOp;

    string constant IMO_NUMBER = "IMO999111";
    uint256 constant SUPPLIER_ID = 5005;

    function setUp() public {
        bargeOwner = vm.createWallet("bargeOwner");
        chiefOwner = vm.createWallet("chiefOwner");

        entryPointBarge = new EntryPoint();
        entryPointChief = new EntryPoint();

        registry = new BunkerControl();

        vm.prank(bargeOwner.addr);
        bargeAA = new MinimalAccount(address(entryPointBarge));

        vm.prank(chiefOwner.addr);
        chiefAA = new MinimalAccount(address(entryPointChief));

        registry.registerShip(IMO_NUMBER, address(chiefAA));
        registry.registerSupplier(SUPPLIER_ID, address(bargeAA));

        sendPackedUserOp = new SendPackedUserOp();
    }

    function testAARegistration() public view {
        assertEq(registry.shipToChiefEng(IMO_NUMBER), address(chiefAA));
        assertEq(registry.supplierToBarge(SUPPLIER_ID), address(bargeAA));

        assertEq(address(bargeAA.getEntryPoint()), address(entryPointBarge));
        assertEq(address(chiefAA.getEntryPoint()), address(entryPointChief));

        console.log("Barge AA deployed with EntryPoint:", address(entryPointBarge));
        console.log("Chief AA deployed with EntryPoint:", address(entryPointChief));
    }

    function testBargeOwnerCanNominateViaAA() public {
        bytes32 deliveryId = keccak256("DELIVERY_002");
        uint256 expectedSulphur = 500;

        bytes memory nominateData = abi.encodeWithSelector(
            BunkerControl.nominateBunker.selector, deliveryId, IMO_NUMBER, SUPPLIER_ID, expectedSulphur
        );

        vm.prank(bargeOwner.addr);
        bargeAA.execute(address(registry), 0, nominateData);

        BunkerControl.BunkerNote memory note = registry.getNote(deliveryId);

        assertEq(uint256(note.status), uint256(BunkerControl.BunkerStatus.Nominated));
        assertEq(note.imoNumber, IMO_NUMBER);
        assertEq(note.supplierId, SUPPLIER_ID);
        assertEq(note.sulphurContent, expectedSulphur);

        console.log("Nomination successful for Delivery ID:", vm.toString(deliveryId));
        console.log("Bunker Status:", uint256(note.status));
    }

    function testEntryPointBargeCanNominate() public {
        bytes32 deliveryId = keccak256("DELIVERY_AA_003");
        uint256 expectedSulphur = 500;
        address randomUser = makeAddr("bundler");

        bytes memory nominateData = abi.encodeWithSelector(
            BunkerControl.nominateBunker.selector, deliveryId, IMO_NUMBER, SUPPLIER_ID, expectedSulphur
        );

        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, address(registry), 0, nominateData);

        PackedUserOperation memory packedUserOp = sendPackedUserOp.signBunkerOperation(
            executeCallData,
            address(entryPointBarge), //entry point
            address(bargeAA), //AA for barge
            bargeOwner.privateKey
        );

        vm.deal(address(bargeAA), 1 ether);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOp;

        vm.prank(randomUser);
        entryPointBarge.handleOps(ops, payable(randomUser));

        BunkerControl.BunkerNote memory note = registry.getNote(deliveryId);

        assertEq(uint256(note.status), uint256(BunkerControl.BunkerStatus.Nominated));
        assertEq(note.imoNumber, IMO_NUMBER);
        assertEq(note.supplierId, SUPPLIER_ID);

        console.log("Success: EntryPoint handled nomination for Delivery ID:", vm.toString(deliveryId));
    }
}
