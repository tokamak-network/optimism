package solver

import (
	"context"
	"errors"
	"fmt"
	"log"

	"github.com/ethereum-optimism/optimism/op-challenger/game/fault/types"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
)

type GameSolver struct {
	claimSolver    *claimSolver
	ratAddress     common.Address
	client         *ethclient.Client
	challengerAddr common.Address
}

func NewGameSolver(gameDepth types.Depth, trace types.TraceAccessor) *GameSolver {
	return &GameSolver{
		claimSolver: newClaimSolver(gameDepth, trace),
	}
}

func NewGameSolverWithRAT(gameDepth types.Depth, trace types.TraceAccessor, ratAddr common.Address, client *ethclient.Client, challengerAddr common.Address) *GameSolver {
	return &GameSolver{
		claimSolver:    newClaimSolver(gameDepth, trace),
		ratAddress:     ratAddr,
		client:         client,
		challengerAddr: challengerAddr,
	}
}

func (s *GameSolver) AgreeWithRootClaim(ctx context.Context, game types.Game) (bool, error) {
	return s.claimSolver.agreeWithClaim(ctx, game, game.Claims()[0])
}

// submitCorrectEvidence submits correct evidence to the RAT contract when root claim is correct
func (s *GameSolver) submitCorrectEvidence(ctx context.Context, game types.Game, gameAddr common.Address) error {
	// Get the root claim
	claims := game.Claims()
	if len(claims) == 0 {
		return fmt.Errorf("no claims in game")
	}

	// Check if RAT functionality is enabled
	if s.ratAddress == (common.Address{}) || s.client == nil {
		return nil // RAT not configured, skip
	}

	rootClaim := claims[0]

	// Calculate left child (Attack) position and value
	leftPosition := rootClaim.Position.Attack()
	leftValue, err := s.claimSolver.trace.Get(ctx, game, rootClaim, leftPosition)
	if err != nil {
		return fmt.Errorf("failed to get left child value: %w", err)
	}

	// Calculate right child (Defend) position and value
	rightPosition := rootClaim.Position.Defend()
	rightValue, err := s.claimSolver.trace.Get(ctx, game, rootClaim, rightPosition)
	if err != nil {
		return fmt.Errorf("failed to get right child value: %w", err)
	}

	// Call RAT contract to submit correct evidence
	return s.callRATSubmitCorrectEvidence(ctx, gameAddr, leftValue, rightValue)
}

// callRATSubmitCorrectEvidence calls the RAT contract submitCorrectEvidence function
func (s *GameSolver) callRATSubmitCorrectEvidence(ctx context.Context, gameAddr common.Address, leftValue, rightValue common.Hash) error {
	// TODO: Implement actual contract call to RAT.submitCorrectEvidence
	// This would involve:
	// 1. Creating a transaction to call RAT contract
	// 2. Encoding the function call with parameters: gameAddr, leftValue, rightValue
	// 3. Signing and sending the transaction
	
	log.Printf("RAT: Would submit correct evidence for game %s with left=%s, right=%s", 
		gameAddr.Hex(), leftValue.Hex(), rightValue.Hex())
	
	// For now, just log the action - actual implementation would require:
	// - ABI binding generation for RAT contract
	// - Transaction management
	// - Error handling for contract calls
	
	return nil
}

func (s *GameSolver) CalculateNextActions(ctx context.Context, game types.Game) ([]types.Action, error) {
	agreeWithRootClaim, err := s.AgreeWithRootClaim(ctx, game)
	if err != nil {
		return nil, fmt.Errorf("failed to determine if root claim is correct: %w", err)
	}

	// Challenging the L2 block number will only work if we have the same output root as the claim
	// Otherwise our output root preimage won't match. We can just proceed and invalidate the output root by disputing claims instead.
	if agreeWithRootClaim {
		if challenge, err := s.claimSolver.trace.GetL2BlockNumberChallenge(ctx, game); errors.Is(err, types.ErrL2BlockNumberValid) {
			// We agree with the L2 block number, proceed to processing claims
			
			// RAT attention test evidence submission
			if err := s.submitCorrectEvidence(ctx, game, common.Address{}); err != nil {
				log.Printf("RAT: Failed to submit correct evidence: %v", err)
			}

		} else if err != nil {
			// Failed to check L2 block validity
			return nil, fmt.Errorf("failed to determine L2 block validity: %w", err)
		} else {
			return []types.Action{
				{
					Type:                          types.ActionTypeChallengeL2BlockNumber,
					InvalidL2BlockNumberChallenge: challenge,
				},
			}, nil
		}
	}

	var actions []types.Action
	agreedClaims := newHonestClaimTracker()
	if agreeWithRootClaim {
		agreedClaims.AddHonestClaim(types.Claim{}, game.Claims()[0])
	}
	for _, claim := range game.Claims() {
		var action *types.Action
		if claim.Depth() == game.MaxDepth() {
			action, err = s.calculateStep(ctx, game, claim, agreedClaims)
		} else {
			action, err = s.calculateMove(ctx, game, claim, agreedClaims)
		}
		if err != nil {
			// Unable to continue iterating claims safely because we may not have tracked the required honest moves
			// for this claim which affects the response to later claims.
			// Any actions we've already identified are still safe to apply.
			return actions, fmt.Errorf("failed to determine response to claim %v: %w", claim.ContractIndex, err)
		}
		if action == nil {
			continue
		}
		actions = append(actions, *action)
	}
	return actions, nil
}

func (s *GameSolver) calculateStep(ctx context.Context, game types.Game, claim types.Claim, agreedClaims *honestClaimTracker) (*types.Action, error) {
	if claim.CounteredBy != (common.Address{}) {
		return nil, nil
	}
	step, err := s.claimSolver.AttemptStep(ctx, game, claim, agreedClaims)
	if err != nil {
		return nil, err
	}
	if step == nil {
		return nil, nil
	}
	return &types.Action{
		Type:        types.ActionTypeStep,
		ParentClaim: step.LeafClaim,
		IsAttack:    step.IsAttack,
		PreState:    step.PreState,
		ProofData:   step.ProofData,
		OracleData:  step.OracleData,
	}, nil
}

func (s *GameSolver) calculateMove(ctx context.Context, game types.Game, claim types.Claim, honestClaims *honestClaimTracker) (*types.Action, error) {
	move, err := s.claimSolver.NextMove(ctx, claim, game, honestClaims)
	if err != nil {
		return nil, fmt.Errorf("failed to calculate next move for claim index %v: %w", claim.ContractIndex, err)
	}
	if move == nil {
		return nil, nil
	}
	honestClaims.AddHonestClaim(claim, *move)
	if game.IsDuplicate(*move) {
		return nil, nil
	}
	return &types.Action{
		Type:        types.ActionTypeMove,
		IsAttack:    !game.DefendsParent(*move),
		ParentClaim: game.Claims()[move.ParentContractIndex],
		Value:       move.Value,
	}, nil
}
