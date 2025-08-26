### Game Start Flow
1. Monitor → Game Detection
   ↓
2. Scheduler → Register in Job Queue
   ↓
3. Worker(Challenger) → Receive Job Assignment (j := <-in)
   ↓
4. GamePlayer.ProgressGame() → Game Progress
   ↓
5. Agent.Act() → Action Calculation and Execution
   ↓
6. performAction() → Actual Blockchain Transaction Transmission
   ↓
7. Responder.PerformAction() → Contract Call


### Flow for Challenger to Verify Root Claim's True/False
1. Agent.Act() → Start Game Action
   ↓
2. GameSolver.CalculateNextActions() → Calculate Next Actions
   ↓
3. GameSolver.AgreeWithRootClaim() → Verify Root Claim
   ↓
4. claimSolver.agreeWithClaim() → Compare Claim Values
   ↓
5. TraceProvider.Get() → Calculate Values Using Actual Execution Trace
   ↓
6. bytes.Equal(ourValue, claim.Value) → True/False Determination

'''
// op-challenger/game/fault/solver/game_solver.go
func (s *GameSolver) CalculateNextActions(ctx context.Context, game types.Game) ([]types.Action, error) {
    // 🔥 Check if root claim is correct
	agreeWithRootClaim, err := s.AgreeWithRootClaim(ctx, game)
	if err != nil {
		return nil, fmt.Errorf("failed to determine if root claim is correct: %w", err)
	}

	// Challenging the L2 block number will only work if we have the same output root as the claim
	// Otherwise our output root preimage won't match. We can just proceed and invalidate the output root by disputing claims instead.
	if agreeWithRootClaim {
         // If root is correct → Try L2 block number challenge
		if challenge, err := s.claimSolver.trace.GetL2BlockNumberChallenge(ctx, game); errors.Is(err, types.ErrL2BlockNumberValid) {
			// We agree with the L2 block number, proceed to processing claims
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

    // If root is wrong → Attack/defend claims one by one
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

'''
