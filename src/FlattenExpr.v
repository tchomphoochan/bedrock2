Require Import lib.LibTactics.
Require Import compiler.Common.
Require Import compiler.ResMonad.
Require compiler.ExprImp.
Require compiler.FlatImp.
Require Import Coq.Logic.FunctionalExtensionality.
Require Import compiler.Axioms.
Require Import compiler.StateCalculus.
Require Import compiler.NameGen.

(* TODO automate such that we don't to Require this, and not always specify which lemma to use *)
Require compiler.StateCalculusTacticTest.

Open Scope Z.

Section FlattenExpr.

  Context {w: nat}. (* bit width *)
  Context {var: Set}.
  Context {eq_var_dec: DecidableEq var}.
  Context {state: Type}.
  Context {stateMap: Map state var (word w)}.
  Context {vars: Type}.
  Context {varset: set vars var}.
  Context {NGstate: Type}.
  Context {NG: NameGen var vars NGstate}.

  (* returns and var into which result is saved, and new fresh name generator state
     TODO use state monad? *)
  Fixpoint flattenExpr(ngs: NGstate)(e: @ExprImp.expr w var):
    (@FlatImp.stmt w var * var * NGstate) :=
    match e with
    | ExprImp.ELit n =>
        let '(x, ngs') := genFresh ngs in
        (FlatImp.SLit x n, x, ngs')
    | ExprImp.EVar x =>
        (* (FlatImp.SSkip, x, ngs)  would be simpler but doesn't satisfy the invariant that
           the returned var is in modVars of the returned statement *)
        let '(y, ngs') := genFresh ngs in
        (FlatImp.SSet y x, y, ngs')
    | ExprImp.EOp op e1 e2 =>
        let '(s1, r1, ngs') := flattenExpr ngs e1 in
        let '(s2, r2, ngs'') := flattenExpr ngs' e2 in
        let '(x, ngs''') := genFresh ngs'' in
        (FlatImp.SSeq s1 (FlatImp.SSeq s2 (FlatImp.SOp x op r1 r2)), x, ngs''')
    end.

  (* returns statement and new fresh name generator state *)
  Fixpoint flattenStmt(ngs: NGstate)(s: @ExprImp.stmt w var):
    (@FlatImp.stmt w var * NGstate) :=
    match s with
    | ExprImp.SSet x e =>
        let '(e', r, ngs') := flattenExpr ngs e in
        (FlatImp.SSeq e' (FlatImp.SSet x r), ngs')
    | ExprImp.SIf cond sThen sElse =>
        let '(cond', r, ngs') := flattenExpr ngs cond in
        let '(sThen', ngs'') := flattenStmt ngs' sThen in
        let '(sElse', ngs''') := flattenStmt ngs'' sElse in
        (FlatImp.SSeq cond' (FlatImp.SIf r sThen' sElse'), ngs''')
    | ExprImp.SWhile cond body =>
        let '(cond', r, ngs') := flattenExpr ngs cond in
        let '(body', ngs'') := flattenStmt ngs' body in
        (FlatImp.SLoop cond' r body', ngs'')
    | ExprImp.SSeq s1 s2 =>
        let '(s1', ngs') := flattenStmt ngs s1 in
        let '(s2', ngs'') := flattenStmt ngs' s2 in
        (FlatImp.SSeq s1' s2', ngs'')
    | ExprImp.SSkip => (FlatImp.SSkip, ngs)
    end.

(*
  Lemma set_extensionality: forall (T: Type) s1 s2,
    (forall (x: T), x \in s1 <-> x \in s2) -> s1 = s2.
  Proof.
    intros. extensionality x. apply prop_ext. apply H.
  Qed.
*)
(*
Ltac set_solver E :=
  repeat autounfold with unf_set_defs in *;
  destruct_products;
  intros;
  specialize_with E;
  autorewrite with rew_set_op_specs in *;
  subst;
  tauto.
*)

Ltac set_solver E :=
  repeat autounfold with unf_set_defs in *;
  destruct_products;
  intros;
  specialize_with E;
  autorewrite with rew_set_op_specs in *;
  intuition (subst; auto).

  Lemma flattenExpr_freshVarUsage: forall e ngs ngs' s v,
    flattenExpr ngs e = (s, v, ngs') ->
    subset (allFreshVars ngs') (allFreshVars ngs).
  Proof.
    induction e; intros; repeat (inversionss; try destruct_one_match_hyp);
    repeat match goal with
    | H: _ |- _ => apply genFresh_spec in H
    end;
    try (
      specializes IHe1; [ eassumption | ];
      specializes IHe2; [ eassumption | ]
    );
    set_solver var.
  Qed.

  Lemma flattenExpr_modifies_resVar: forall e s ngs ngs' resVar,
    flattenExpr ngs e = (s, resVar, ngs') ->
    resVar \in (FlatImp.modVars s).
  Proof.
    intros.
    destruct e; repeat (inversionss; try destruct_one_match_hyp); simpl in *; state_calc.
  Qed.

  Lemma flattenExpr_resVar: forall e s ngs ngs' resVar,
    flattenExpr ngs e = (s, resVar, ngs') ->
    ~ resVar \in (allFreshVars ngs').
  Proof.
    intros. destruct e; repeat (inversionss; try destruct_one_match_hyp); simpl in *;
    repeat match goal with
    | H: _ |- _ => apply genFresh_spec in H
    end;
    state_calc.
  Qed.

  Lemma flattenExpr_modVars_spec: forall e s ngs ngs' resVar,
    flattenExpr ngs e = (s, resVar, ngs') ->
    subset (FlatImp.modVars s) (diff (allFreshVars ngs) (allFreshVars ngs')).
  Proof.
    induction e; intros; repeat (inversionss; try destruct_one_match_hyp);
    simpl;
    try (
      specializes IHe1; [ eassumption | ];
      specializes IHe2; [ eassumption | ]
    );
    repeat match goal with
    | H: _ |- _ => apply genFresh_spec in H
    | H: _ |- _ => apply flattenExpr_freshVarUsage in H
    end;
    set_solver var.
  Qed.

  Lemma flattenStmt_freshVarUsage: forall s s' ngs1 ngs2,
    flattenStmt ngs1 s = (s', ngs2) ->
    subset (allFreshVars ngs2) (allFreshVars ngs1).
  Proof.
    induction s; intros; repeat (inversionss; try destruct_one_match_hyp);
    repeat match goal with
    | H: _ |- _ => apply genFresh_spec in H
    | H: _ |- _ => apply flattenExpr_freshVarUsage in H
    end;
    repeat match goal with
    | IH: forall _ _ _, _ = _ -> _ |- _ => specializes IH; [ eassumption | ]
    end;
    set_solver var.
  Qed.

  Lemma increase_fuel_still_Success: forall fuel1 fuel2 initial s final,
    (fuel1 <= fuel2)%nat ->
    FlatImp.eval_stmt fuel1 initial s = Success final ->
    FlatImp.eval_stmt fuel2 initial s = Success final.
  Proof.
    induction fuel1; introv L Ev.
    - inversions Ev.
    - destruct fuel2; [omega|]. destruct s.
      + exact Ev.
      + exact Ev.
      + exact Ev.
      + simpl in *. destruct_one_match; try discriminate.
        erewrite IHfuel1; [reflexivity | omega | exact Ev].
      + apply FlatImp.invert_eval_SLoop in Ev.
        destruct Ev as [Ev | Ev]. 
        * destruct Ev as [Ev C]. 
          simpl. erewrite IHfuel1; [|omega|eassumption].
          rewrite C. simpl. destruct_one_match; [reflexivity | contradiction].
        * destruct Ev as [mid2 [mid3 [cv [Ev1 [C1 [C2 [Ev2 Ev3]]]]]]].
          simpl.
          erewrite IHfuel1; [|omega|eassumption].
          erewrite IHfuel1; [|omega|eassumption].
          erewrite IHfuel1; [|omega|eassumption].
          rewrite C1. simpl.
          destruct_one_match; [ contradiction | reflexivity ].
     + apply FlatImp.invert_eval_SSeq in Ev.
       destruct Ev as [mid [Ev1 Ev2]].
       simpl.
       erewrite IHfuel1; [|omega|eassumption].
       erewrite IHfuel1; [|omega|eassumption].
       reflexivity.
     + simpl. inversionss. reflexivity.
  Qed.

  Lemma put_idemp: forall s x v,
    get s x = Some v ->
    s = put s x v.
  Proof.
    intros. apply map_extensionality. intros.
    rewrite get_put. destruct_one_match; congruence.
  Qed.

  Ltac pose_flatten_var_ineqs :=
    repeat match goal with
    | H: _ |- _ => unique apply flattenExpr_freshVarUsage in copy of H
    | H: _ |- _ => unique apply FlatImp.modVarsSound in copy of H
    | H: _ |- _ => unique apply flattenExpr_modifies_resVar in copy of H
    | H: _ |- _ => unique apply flattenExpr_modVars_spec in copy of H
    end.

Ltac state_calc_newV0 varT valT :=
  repeat autounfold with unfold_state_calculus in *;
  intros;
  repeat autounfold with unf_set_defs in *;
  destruct_products;
  intros;
  repeat (specialize_with varT || specialize_with valT);
  autorewrite with rew_set_op_specs in *;
  intuition (subst; auto || congruence).

Ltac state_calc varT valT :=
  repeat autounfold with unfold_state_calculus in *;
  intros;
  repeat autounfold with unf_set_defs in *;
  destruct_products;
  intros;
  rewrite? get_put in *;
  repeat (specialize_with varT || specialize_with valT);
  autorewrite with rew_set_op_specs in *;
  repeat (intuition (subst; auto || congruence) || destruct_one_dec_eq).

  Tactic Notation "nofail" tactic3(t) := first [ t | fail 1000 "should not have failed"].

  (* Note: If you want to get in the conclusion
     "only_differ initialL (vars_range firstFree (S resVar)) finalL"
     this needn't be part of this lemma, because it follows from
     flattenExpr_modVars_spec and FlatImp.modVarsSound *)
  Lemma flattenExpr_correct_aux: forall e ngs1 ngs2 resVar s initialH initialL res,
    flattenExpr ngs1 e = (s, resVar, ngs2) ->
    extends initialL initialH ->
    undef initialH (allFreshVars ngs1) ->
    ExprImp.eval_expr initialH e = Some res ->
    exists fuel finalL,
      FlatImp.eval_stmt fuel initialL s = Success finalL /\
      get finalL resVar = Some res.
  Proof.
    induction e; introv F Ex U Ev.
    - repeat (inversionss; try destruct_one_match_hyp).
      exists 1%nat (put initialL resVar res).
      split; state_calc var (word w).
    - repeat (inversionss; try destruct_one_match_hyp).
      exists 1%nat (put initialL resVar res). repeat split.
      + simpl. unfold extends in Ex. apply Ex in H0. rewrite H0. simpl. reflexivity.
      + state_calc var (word w).
    - repeat (inversionss; try destruct_one_match_hyp).
      pose_flatten_var_ineqs.
      specialize (IHe1 _ _ _ _ _ _ w0 E Ex).
      specializes IHe1. {
        clear IHe2.
        state_calc var (word w).
      }
      { assumption. }
      destruct IHe1 as [fuel1 [midL [Ev1 G1]]].
      progress pose_flatten_var_ineqs.
      specialize (IHe2 _ _ _ _ initialH midL w1 E0).
      specializes IHe2.
      { state_calc var (word w). }
      { state_calc var (word w). }
      { assumption. }
      destruct IHe2 as [fuel2 [preFinalL [Ev2 G2]]].
      remember (Datatypes.S (Datatypes.S (fuel1 + fuel2))) as f0.
      remember (Datatypes.S (fuel1 + fuel2)) as f.
      exists (Datatypes.S f0) (put preFinalL resVar (Op.eval_binop op w0 w1)).
      pose_flatten_var_ineqs.
      split.
      + simpl. erewrite increase_fuel_still_Success; [| |eassumption]; [|omega].
        apply increase_fuel_still_Success with (fuel1 := f0); [omega|].
        subst f0. simpl.
        erewrite (increase_fuel_still_Success _ _ midL); [| |eassumption]; [|omega].
        subst f. simpl.
        assert (get preFinalL v = Some w0) as G1'. {
          state_calc var (word w).
        }
        rewrite G1'. simpl. rewrite G2. simpl. reflexivity.
      + apply get_put_same.
  Qed.

  Lemma flattenStmt_correct_aux:
    forall fuelH sH sL ngs ngs' initialH finalH initialL,
    flattenStmt ngs sH = (sL, ngs') ->
    extends initialL initialH ->
    undef initialH (allFreshVars ngs) ->
    disjoint (ExprImp.modVars sH) (allFreshVars ngs) ->
    ExprImp.eval_stmt fuelH initialH sH = Some finalH ->
    exists fuelL finalL,
      FlatImp.eval_stmt fuelL initialL sL = Success finalL /\
      extends finalL finalH.
  Proof.
    induction fuelH; introv F Ex U Di Ev; [solve [inversionss] |].
    destruct sH.
    - apply ExprImp.invert_eval_SSet in Ev.
      destruct Ev as [v [Ev Eq]].
      repeat (inversionss; try destruct_one_match_hyp).
      pose proof (flattenExpr_correct_aux _ _ _ _ _ _ _ _ E Ex U Ev) as P.
      destruct P as [fuelL [prefinalL [Evs G]]].
      remember (Datatypes.S fuelL) as SfuelL.
      exists (Datatypes.S SfuelL). eexists. repeat split.
      + simpl.
        assert (FlatImp.eval_stmt SfuelL initialL s = Success prefinalL) as Evs'. {
          eapply increase_fuel_still_Success; [|eassumption]. omega.
        }
        rewrite Evs'. subst SfuelL. simpl. rewrite G. simpl. reflexivity.
      + clear IHfuelH. apply compiler.StateCalculusTacticTest.extends_put_same.
        eapply compiler.StateCalculusTacticTest.extends_if_only_differ_in_undef;
        [ eassumption | eassumption | ].
        pose_flatten_var_ineqs.
        eapply StateCalculusTacticTest.only_differ_subset; [|eassumption].
        set_solver var.
    - inversions F. repeat destruct_one_match_hyp. destruct_pair_eqs. subst.
      apply ExprImp.invert_eval_SIf in Ev.
      destruct Ev as [cv [Evc Ev]].
      pose_flatten_var_ineqs.
      rename cond into condH, s into condL, s0 into sL1, s1 into sL2.
      pose proof (flattenExpr_correct_aux _ _ _ _ _ _ _ cv E Ex) as P.
      specializes P; [eassumption|eassumption|].
      destruct P as [fuelLcond [initial2L [Evcond G]]].
      destruct Ev as [[Ne EvThen] | [Eq EvElse]].
      + specialize (IHfuelH sH1 sL1 n n0 initialH finalH initial2L E0).
        specializes IHfuelH.
        * assert (only_differ initialL (vars_range firstFree (S v)) initial2L) as D. {
            apply proj1 in E2. rewrite <- E2. eapply FlatImp.modVarsSound. eassumption.
          }
          (* TODO this should be state_calc *)
          clear - U D Ex E3 E4.
          eapply compiler.StateCalculusTacticTest.extends_if_only_differ_in_undef.
          3: exact D. 1: exact Ex.
          clear Ex D.
          unfold undef in *. intros. specialize (U x).
          rewrite? in_vars_range in *.
          apply U. myomega.
        * eapply compiler.StateCalculusTacticTest.undef_shrink; [eassumption|].
          apply vars_range_subset; myomega.
        * simpl in Di.
          destruct E2 as [_ E2].
          clear - E2 E3 E4 Di U.
          unfold disjoint.
          intros. specialize (Di x).
          Fail rewrite union_spec in *. (* why?? *)
          rewrite union_spec in Di. (* while this one works!! *)
          rewrite in_vars_range in *.
          intuition myomega.
        * exact EvThen.
        * destruct IHfuelH as [fuelL [finalL [Evbranch Ex2]]].
          exists (Datatypes.S (fuelLcond + (Datatypes.S fuelL))). eexists.
          refine (conj _ Ex2).
          simpl.
          pose proof increase_fuel_still_Success as P.
          assert (fuelLcond <= fuelLcond + (Datatypes.S fuelL))%nat as IE by omega.
          specializes P. { eapply IE. } { eapply Evcond. }
          rewrite P. clear IE P.
          pose proof increase_fuel_still_Success as P.
          assert (Datatypes.S fuelL <= fuelLcond + (Datatypes.S fuelL))%nat as IE by omega.
          eapply (P _ _ _ _ _ IE). clear IE P.
          simpl. rewrite G. simpl. destruct_one_match; [contradiction|].
          exact Evbranch.
      + specialize (IHfuelH sH2 sL2 v0 newFirstFree initialH finalH initial2L E1).
        specializes IHfuelH.
        * assert (only_differ initialL (vars_range firstFree (S v)) initial2L) as D. {
            apply proj1 in E2. rewrite <- E2. eapply FlatImp.modVarsSound. eassumption.
          } (* TODO this should be state_calc *)
          clear - U D Ex E3 E4.
          eapply compiler.StateCalculusTacticTest.extends_if_only_differ_in_undef.
          3: exact D. 1: exact Ex.
          clear Ex D.
          unfold undef in *. intros. specialize (U x).
          rewrite? in_vars_range in *.
          apply U. myomega.
        * eapply compiler.StateCalculusTacticTest.undef_shrink; [eassumption|].
          apply vars_range_subset; myomega.
        * simpl in Di.
          destruct E2 as [_ E2].
          clear - E2 E3 E4 Di U.
          unfold disjoint.
          intros. specialize (Di x).
          Fail rewrite union_spec in *. (* why?? *)
          rewrite union_spec in Di. (* while this one works!! *)
          rewrite in_vars_range in *.
          intuition myomega.
        * exact EvElse.
        * destruct IHfuelH as [fuelL [finalL [Evbranch Ex2]]].
          exists (Datatypes.S (fuelLcond + (Datatypes.S fuelL)))%nat. eexists.
          refine (conj _ Ex2).
          simpl.
          pose proof increase_fuel_still_Success as P.
          assert (fuelLcond <= fuelLcond + (Datatypes.S fuelL))%nat as IE by omega.
          specializes P. { eapply IE. } { eapply Evcond. }
          rewrite P. clear IE P.
          pose proof increase_fuel_still_Success as P.
          assert (Datatypes.S fuelL <= fuelLcond + (Datatypes.S fuelL))%nat as IE by omega.
          eapply (P _ _ _ _ _ IE). clear IE P.
          simpl. rewrite G. simpl. destruct_one_match; [|contradiction].
          exact Evbranch.
    - admit. (* TODO while *)
    - apply ExprImp.invert_eval_SSeq in Ev.
      destruct Ev as [middleH [Ev1 Ev2]].
      simpl in F. do 2 destruct_one_match_hyp. inversions F.
      pose proof IHfuelH as IHfuelH2.
      specializes IHfuelH.
      1: exact E. 1: exact Ex. 3: exact Ev1.
      { eapply StateCalculusTacticTest.undef_shrink; [eassumption|].
        unfold subset. intro.
        rewrite? in_vars_range. pose_flatten_var_ineqs. intros. myomega. }
      { simpl in Di. admit. (* TODO *)
      
      }
      destruct IHfuelH as [fuelL1 [middleL [EvL1 Ex1]]].
      rename IHfuelH2 into IHfuelH.
      rename s into sL1, s0 into sL2.
      specialize (IHfuelH sH2 sL2 v newFirstFree middleH finalH middleL).
      specializes IHfuelH.
      1: exact E0. 1: exact Ex1. 3: exact Ev2.
      { admit. (* TODO *) }
      { pose proof (ExprImp.modVarsSound _ _ _ _ Ev1) as D1.
        pose_flatten_var_ineqs.
        clear -D1 Di U. (* tricky, need to relate modVars range to "fresh" range *)
        admit. }
      
      admit. (* TODO seq *)

    - apply ExprImp.invert_eval_SSkip in Ev. subst finalH.
      simpl in F. inversions F.
      exists 1%nat initialL. auto.
  Qed.

End FlattenExpr.
