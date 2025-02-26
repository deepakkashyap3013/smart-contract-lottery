// SPDX-License-Identifier: SEE MIT
pragma solidity 0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig, CodeConstants} from "script/HelperConfig.s.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test, Script, CodeConstants {
    Raffle private raffle;
    HelperConfig private helperConfig;

    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    address public PLAYER = makeAddr("player");
    uint256 public STARTING_PLAYER_BALANCE = 10 ether;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinatorV2;
    bytes32 gasLane;
    uint256 subscriptionId;
    uint32 callbackGasLimit;

    function setUp() external {
        DeployRaffle deployRaffle = new DeployRaffle();
        (raffle, helperConfig) = deployRaffle.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinatorV2 = config.vrfCoordinatorV2;
        gasLane = config.gasLane;
        subscriptionId = config.subscriptionId;
        callbackGasLimit = config.callbackGasLimit;

        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    function testInitRaffleStateIsOpen() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    /** Enter Raffle tests */
    function testEnterRaffleFailNotEnoughEntranceFee() public {
        // Arrange
        vm.prank(PLAYER);
        // Act/ Assert
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        // Arrange
        vm.prank(PLAYER);
        // Act
        raffle.enterRaffle{value: entranceFee}();
        // Assert
        address player = raffle.getPlayer(0);
        assert(player == PLAYER);
    }

    function testEnterRaffleEmitEvent() public {
        vm.prank(PLAYER);

        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(PLAYER); //  -- expectation

        // trigger the emission of the event through transaction
        raffle.enterRaffle{value: entranceFee}();
    }

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep(""); // <- quite interesting setups has been done inorder to pass this test

        // Act/Assert
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        raffle.enterRaffle{value: entranceFee}();
    }

    /** Checkup Keeps */
    function testCheckUpkeepReturnsFalseIfHasNoBalance() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleIsntOpen() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersGood() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(upkeepNeeded);
    }

    /** Perform upkeep */
    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act / Assert
        // It doesnt revert
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();
        // Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                rState
            )
        );
        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        vm.recordLogs();
        raffle.performUpkeep(""); // emits the requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        // Assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1); // 1 = calculating
    }

    /** Fulfill random words */
    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    // this is some kind of fuzz testing :) will be learning in later sections
    // [PASS] testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256) (runs: 256, μ: 82445, ~: 82445)
    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    ) public raffleEntered skipFork {
        // Arrange / Act / Assert
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinatorV2).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney()
        public
        raffleEntered
        skipFork
    {
        address expectedWinner = address(1); // we are expecting address 1 to win

        // Arrange
        uint256 additionalPlayers = 3; // so total of 4 players entered 1st being from the raffleEntered
        uint256 startingIndex = 1;

        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalPlayers;
            i++
        ) {
            address player = address(uint160(i));
            hoax(player, 1 ether);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 startingBalance = expectedWinner.balance;

        // Act
        vm.recordLogs();
        raffle.performUpkeep(""); // emits the requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinatorV2).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        // Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entranceFee * (additionalPlayers + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0); // Open again
        assert(winnerBalance == startingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }
}
