// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console, Vm} from "forge-std/Test.sol";
import {MaritimeRegistryAAOwner} from "../src/MaritimeRegistryAAOwner.sol";
import {MinimalAccount} from "../src/MinimalAccount.sol";
import {DeployMinimal} from "../script/DeployMinimal.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {EntryPoint} from "lib/account-abstraction/contracts/core/EntryPoint.sol";

contract MaritimeRegistryAAOwnerTest is Test {
    MaritimeRegistryAAOwner public registry;
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
    }

    function testRegistryOwnershipAndMappings() public view {
        assertEq(registry.owner(), address(minimalAccount));

        assertEq(registry.shipToChiefEng(IMO_NUMBER), chiefWallet.addr);
        assertEq(registry.supplierToBarge(SUPPLIER_ID), bunkerWallet.addr);

        console.log("Registry Owner (AA):", registry.owner());
        console.log("Chief Engineer Registered:", chiefWallet.addr);
        console.log("Bunker Supplier Registered:", bunkerWallet.addr);
    }

    //todo :
    //implement other testcases: full work flow of the maritime registry contract using the AA(minimal account) -> owner
}
