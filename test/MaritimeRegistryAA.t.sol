// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MaritimeRegistry} from "../src/MaritimeRegistry.sol";
import {MinimalAccount} from "../src/MinimalAccount.sol";
import {DeployMinimal} from "../script/DeployMinimal.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {SendPackedUserOp} from "../script/SendPackedUserOp.s.sol";
import {SendPackedUserOp, PackedUserOperation, IEntryPoint} from "script/SendPackedUserOp.s.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract MaritimeRegistryTest is Test {
    MaritimeRegistry public registry;
    MinimalAccount public minimalAccount;
    HelperConfig public helperConfig;
    ERC20Mock public usdc;
    SendPackedUserOp public sendPackedUserOp;

    address randomuser = makeAddr("randomUser");

    string constant IMO_NUMBER = "IMO9876543";
    uint256 constant SUPPLIER_ID = 101;
    address public chiefEngineer = makeAddr("chiefEngineer");

    function setUp() public {
        DeployMinimal deployMinimal = new DeployMinimal();
        (helperConfig, minimalAccount) = deployMinimal.deployMinimalAccount();

        registry = new MaritimeRegistry(); //add-on

        usdc = new ERC20Mock();
        sendPackedUserOp = new SendPackedUserOp();

        registry.registerShip(IMO_NUMBER, chiefEngineer);
        registry.registerSupplier(SUPPLIER_ID, address(minimalAccount));
    }

    //done
    function testRegistrationDataIsCorrect() public view {
        address registeredChief = registry.shipToChiefEng(IMO_NUMBER);
        assertEq(registeredChief, chiefEngineer);

        address registeredBarge = registry.supplierToBarge(SUPPLIER_ID);
        assertEq(registeredBarge, address(minimalAccount));

        console.log("Registry successfully linked to MinimalAccount at:", registeredBarge);
    }

    //done
    function testOnlyBargeCanNominate() public {
        bytes32 deliveryId = keccak256("DELIVERY_001");
        uint256 expectedSulphur = 500;

        vm.prank(address(minimalAccount));
        registry.nominateBunker(deliveryId, IMO_NUMBER, SUPPLIER_ID, expectedSulphur);

        MaritimeRegistry.BunkerNote memory note = registry.getNote(deliveryId);
        assertEq(uint256(note.status), uint256(MaritimeRegistry.BunkerStatus.Nominated));
        assertEq(note.imoNumber, IMO_NUMBER);
    }

    //done
    //owner of minimal contract -> execute function(owner) -> nominateBunker(minimal contract)
    function testOwnerCanNominateViaExecute() public {
        bytes32 deliveryId = keccak256("DELIVERY_002");
        uint256 expectedSulphur = 500;

        bytes memory nominateData = abi.encodeWithSelector(
            MaritimeRegistry.nominateBunker.selector, deliveryId, IMO_NUMBER, SUPPLIER_ID, expectedSulphur
        );

        vm.prank(minimalAccount.owner());
        minimalAccount.execute(address(registry), 0, nominateData);

        MaritimeRegistry.BunkerNote memory note = registry.getNote(deliveryId);

        assertEq(uint256(note.status), uint256(MaritimeRegistry.BunkerStatus.Nominated));
        assertEq(note.imoNumber, IMO_NUMBER);
        assertEq(note.supplierId, SUPPLIER_ID);

        console.log("Nomination successful via MinimalAccount execution!");
    }

    //done
    //check if the function revets when called by non owner
    function testOwnerCannotNominateViaExecute() public {
        bytes32 deliveryId = keccak256("DELIVERY_002");
        uint256 expectedSulphur = 500;

        bytes memory nominateData = abi.encodeWithSelector(
            MaritimeRegistry.nominateBunker.selector, deliveryId, IMO_NUMBER, SUPPLIER_ID, expectedSulphur
        );

        vm.prank(randomuser);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        minimalAccount.execute(address(registry), 0, nominateData);
    }

    //done
    //check if the script generated signature is valid
    function testRecoverSignedNominateOp() public {
        bytes32 deliveryId = keccak256("DELIVERY_AA_001");
        uint256 expectedSulphur = 500;

        bytes memory nominateData = abi.encodeWithSelector(
            MaritimeRegistry.nominateBunker.selector, deliveryId, IMO_NUMBER, SUPPLIER_ID, expectedSulphur
        );

        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, address(registry), 0, nominateData);

        PackedUserOperation memory packedUserOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );

        bytes32 userOperationHash = IEntryPoint(helperConfig.getConfig().entryPoint).getUserOpHash(packedUserOp);
        address actualSigner =
            ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(userOperationHash), packedUserOp.signature);

        assertEq(actualSigner, minimalAccount.owner());
        console.log("Signature Verified! UserOp for Maritime Registry signed by:", actualSigner);
    }

    //done
    //genarete the userops with the sig -> prank the entry point -> validate function -> return the digest 0
    function testValidationOfNominateUserOp() public {
        bytes32 deliveryId = keccak256("DELIVERY_VAL_001");
        uint256 expectedSulphur = 500;

        bytes memory nominateData = abi.encodeWithSelector(
            MaritimeRegistry.nominateBunker.selector, deliveryId, IMO_NUMBER, SUPPLIER_ID, expectedSulphur
        );
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, address(registry), 0, nominateData);

        PackedUserOperation memory packedUserOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );

        bytes32 userOperationHash = IEntryPoint(helperConfig.getConfig().entryPoint).getUserOpHash(packedUserOp);
        uint256 missingAccountFunds = 1e18;

        vm.deal(address(minimalAccount), 2e18);
        address entryPoint = helperConfig.getConfig().entryPoint;

        vm.prank(entryPoint);
        uint256 validationData = minimalAccount.validateUserOp(packedUserOp, userOperationHash, missingAccountFunds);
        assertEq(validationData, 0);

        assertEq(entryPoint.balance, missingAccountFunds);
    }

    // generate the useops with the owners signature -> alt mempool -> handle ops on entry point -> validate -> execute ->  nominateBunker -> check the registed bunker(Minimal account)-> updates the state
    function testEntryPointCanNominateForBarge() public {
        bytes32 deliveryId = keccak256("DELIVERY_FULL_FLOW_001");
        uint256 expectedSulphur = 500;
        address entryPointAddress = helperConfig.getConfig().entryPoint;

        bytes memory nominateData = abi.encodeWithSelector(
            MaritimeRegistry.nominateBunker.selector, deliveryId, IMO_NUMBER, SUPPLIER_ID, expectedSulphur
        );

        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, address(registry), 0, nominateData);

        PackedUserOperation memory packedUserOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );

        vm.deal(address(minimalAccount), 1e18);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOp;

        vm.prank(randomuser);
        IEntryPoint(entryPointAddress).handleOps(ops, payable(randomuser));

        MaritimeRegistry.BunkerNote memory note = registry.getNote(deliveryId);

        assertEq(uint256(note.status), uint256(MaritimeRegistry.BunkerStatus.Nominated));
        assertEq(note.imoNumber, IMO_NUMBER);
        assertEq(note.supplierId, SUPPLIER_ID);
        assertEq(note.sulphurContent, expectedSulphur);

        console.log("Nomination successfully processed via AA EntryPoint!");
    }
}
