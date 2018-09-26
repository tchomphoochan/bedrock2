Require Import compiler.FlatImp.
Require Import compiler.StateCalculus.
Require Import compiler.StateCalculusTacticTest.
Require Import compiler.Decidable.
Require Import Coq.Lists.List.
Require Import riscv.Utility.
Require Import compiler.Op.
Require Import compiler.util.Map.
Require Import compiler.util.Set.
Require Import compiler.Memory.
Require Import compiler.util.Tactics.

Section TODO.
  Context {K V: Type}.
  Context {Mf: MapFunctions K V}.
  (*
  Axiom get_in_domain: forall k m, k \in (domain m) -> exists v, get m k = Some v.
  Axiom domain_put: forall k v m, domain (put m k v) = union (domain m) (singleton_set k).
  *)

  (* operations *)
  Axiom reverse_get: map K V -> V -> option K.
  Axiom intersect_map: map K V -> map K V -> map K V.
  Axiom remove_by_value: map K V -> V -> map K V.

  (* specs *)
  Axiom put_put_same: forall k v1 v2 m, put (put m k v1) k v2 = put m k v2.
  Axiom reverse_reverse_get: forall k v m, reverse_get m v = Some k -> get m k = Some v.
  Axiom get_in_range: forall k v m, get m k = Some v -> v \in range m.
  Axiom remove_by_value_spec: forall k v m, get (remove_by_value m v) k <> Some v.
  Axiom get_intersect_map: forall k v m1 m2,
      get (intersect_map m1 m2) k = Some v <-> get m1 k = Some v /\ get m2 k = Some v.

  (* TODO some of this should go into state calculus *)
  (* probably derived *)
  Axiom not_in_range_of_remove_by_value: forall m v, ~ v \in range (remove_by_value m v).
  Axiom extends_remove_by_value: forall m v, extends m (remove_by_value m v).
  Axiom extends_intersect_map_l: forall r1 r2, extends r1 (intersect_map r1 r2).
  Axiom extends_intersect_map_r: forall r1 r2, extends r2 (intersect_map r1 r2).
  Axiom extends_intersect_map_lr: forall m11 m12 m21 m22,
      extends m11 m21 ->
      extends m12 m22 ->
      extends (intersect_map m11 m12) (intersect_map m21 m22).
  Axiom intersect_empty_map_l: forall m, intersect_map empty_map m = m.
  Axiom intersect_empty_map_r: forall m, intersect_map m empty_map = m.

  Axiom remove_by_value_put: forall k v m,
      remove_by_value (put m k v) v = remove_by_value m v.
  Axiom remove_by_value_idemp: forall v m,
      remove_by_value (remove_by_value m v) v = remove_by_value m v.
  Axiom extends_remove_by_value_same: forall x m1 m2,
      extends m1 m2 ->
      extends (remove_by_value m1 x) (remove_by_value m2 x).
  Axiom equality_by_extends: forall m1 m2,
      extends m1 m2 ->
      extends m2 m1 ->
      m1 = m2. (* requires functional extensionality, or unique internal representation *)

  Axiom intersect_map_put_put_same: forall m1 m2 k v,
      intersect_map (put m1 k v) (put m2 k v) = put (intersect_map m1 m2) k v.
  Axiom intersect_map_remove_by_value: forall m1 m2 x,
      intersect_map (remove_by_value m1 x) (remove_by_value m2 x)
      = remove_by_value (intersect_map m1 m2) x.

  Axiom intersect_map_assoc: forall m1 m2 m3,
      intersect_map (intersect_map m1 m2) m3 = intersect_map m1 (intersect_map m2 m3).
  Axiom intersect_map_comm: forall m1 m2,
      intersect_map m1 m2 = intersect_map m2 m1.

  Lemma intersect_map_1234_1423: forall m1 m2 m3 m4,
      intersect_map (intersect_map m1 m2) (intersect_map m3 m4) =
      intersect_map (intersect_map m1 m4) (intersect_map m2 m3).
  Proof.
    intros.
    rewrite? intersect_map_assoc.
    f_equal.
    rewrite <- intersect_map_assoc.
    rewrite intersect_map_comm.
    reflexivity.
  Qed.

End TODO.

Local Notation "'bind_opt' x <- a ; f" :=
  (match a with
   | Some x => f
   | None => None
   end)
  (right associativity, at level 70, x pattern).


Section RegAlloc.

  Variable srcvar: Set.
  Context {srcvar_eq_dec: DecidableEq srcvar}.
  Variable impvar: Set.
  Context {impvar_eq_dec: DecidableEq impvar}.
  Variable func: Set.
  Context {func_eq_dec: DecidableEq func}.

  Context {Map: MapFunctions impvar srcvar}.
  Notation srcvars := (@set srcvar (@map_range_set _ _ Map)).
  Notation impvars := (@set impvar (@map_domain_set _ _ Map)).
  Existing Instance map_domain_set.
  Existing Instance map_range_set.

  (* annotated statement: each assignment is annotated with impvar which it assigns,
     loop has map invariant *)
  Inductive astmt: Type :=
    | ASLoad(x: srcvar)(x': impvar)(a: srcvar)
    | ASStore(a: srcvar)(v: srcvar)
    | ASLit(x: srcvar)(x': impvar)(v: Z)
    | ASOp(x: srcvar)(x': impvar)(op: bopname)(y z: srcvar)
    | ASSet(x: srcvar)(x': impvar)(y: srcvar)
    | ASIf(cond: srcvar)(bThen bElse: astmt)
    | ASLoop(body1: astmt)(cond: srcvar)(body2: astmt)
    | ASSeq(s1 s2: astmt)
    | ASSkip
    | ASCall(binds: list (srcvar * impvar))(f: func)(args: list srcvar).

  Local Notation stmt  := (FlatImp.stmt srcvar func). (* input type *)
  Local Notation stmt' := (FlatImp.stmt impvar func). (* output type *)

  (* impvar -> srcvar mappings which are guaranteed to hold after running s
     (under-approximation) *)
  Definition updateWith :=
    fix rec(m: map impvar srcvar)(s: astmt): map impvar srcvar :=
      match s with
      | ASLoad x x' _ | ASLit x x' _ | ASOp x x' _ _ _ | ASSet x x' _ =>
          (* if several impvars store the value of x, they won't all store the value of
             x after the update, but only x' will, because only x' is written in the target
             program, so we first have to remove the others *)
          put (remove_by_value m x) x' x
      | ASStore a v => m
      | ASIf cond s1 s2 => intersect_map (rec m s1) (rec m s2)
      | ASLoop s1 cond s2 =>
          (* mi = map if loop was repeated i times *)
          let m0 := rec m s1 in
          let m1 := rec (rec m0 s2) s1 in
          (*
          let m2 := rec (rec m1 s2) s1 in
          let m3 := rec (rec m2 s2) s1 in
          ...
          all further fixpoint iterations will do the same, so m1=m2=m3=...,
          so no need to perform them *)
          intersect_map m0 m1
      | ASSeq s1 s2 => rec (rec m s1) s2
      | ASSkip => m
      | ASCall binds f args => empty_map (* TODO *)
      end.

  Lemma updateWith_idemp: forall s m1 m2,
      m2 = updateWith m1 s ->
      updateWith m2 s = m2.
  Proof.
    induction s; intros; simpl in *;
      try reflexivity;
      try (subst; apply put_put_same).
(*
    {
      erewrite IHs1 with (m2 := m2); [erewrite IHs2 with (m2 := m2)|].
      subst.
      - admit. (* ok *)
      - symmetry. eapply IHs2. (* stuck in a loop *)
*)
  Abort.

  Hint Resolve
       extends_put_same
       extends_remove_by_value_same
       extends_intersect_map_lr
       extends_refl
    : map_hints.

  Hint Rewrite
       remove_by_value_put
       remove_by_value_idemp
       intersect_map_put_put_same
       intersect_map_remove_by_value
       intersect_empty_map_l
       intersect_empty_map_r
    : map_rew.

  Hint Extern 1 => autorewrite with map_rew : map_hints.

  Lemma updateWith_monotone: forall s m1 m2,
      extends m1 m2 ->
      extends (updateWith m1 s) (updateWith m2 s).
  Proof.
    induction s; intros; simpl in *; eauto 7 with map_hints.
  Qed.

  Lemma updateWith_intersect_map: forall s m1 m2,
      updateWith (intersect_map m1 m2) s = intersect_map (updateWith m1 s) (updateWith m2 s).
  Proof.
    induction s; intros; simpl in *; eauto with map_hints.
    - rewrite IHs1. rewrite IHs2.
      forget (updateWith m1 s1) as m11.
      forget (updateWith m1 s2) as m12.
      forget (updateWith m2 s1) as m21.
      forget (updateWith m2 s2) as m22.
      rewrite? intersect_map_assoc.
      f_equal.
      rewrite <-? intersect_map_assoc.
      f_equal.
      apply intersect_map_comm.
    - rewrite IHs1. rewrite IHs2. rewrite IHs1.
      forget (updateWith (updateWith (updateWith m2 s1) s2) s1) as m2121.
      forget (updateWith (updateWith (updateWith m1 s1) s2) s1) as m1121.
      forget (updateWith m1 s1) as m11.
      forget (updateWith m2 s1) as m21.
      rewrite? intersect_map_assoc.
      f_equal.
      rewrite <-? intersect_map_assoc.
      f_equal.
      apply intersect_map_comm.
    - rewrite IHs1. rewrite IHs2. reflexivity.
  Qed.

  Lemma updateWith_updateWith_extends_updateWith: forall s m,
      extends (updateWith (updateWith m s) s) (updateWith m s).
  Proof.
    induction s; intros; simpl in *; eauto with map_hints.

    (* rewrite? updateWith_intersect_map.*)


    - state_calc_generic impvar srcvar.
      rewrite get_intersect_map in *.
      destruct H.
  Abort.

  Lemma updateWith_extends_updateWith_updateWith: forall s m,
      extends (updateWith m s) (updateWith (updateWith m s) s).
  Proof.
  Abort.

  Lemma updateWith_121: forall s1 s2 m,
      updateWith (updateWith (updateWith m s1) s2) s1 = updateWith (updateWith m s2) s1.
  Proof.
    induction s1; intros; simpl in *; eauto with map_hints.
    Focus 6. {

  Admitted.

  Lemma updateWith_idemp_wishful: forall s m,
      updateWith (updateWith m s) s = updateWith m s.
  Proof.
    intros. apply (updateWith_121 s ASSkip m).
  Qed.


  Lemma updateWith_idemp: forall s m,
      updateWith (updateWith m s) s = updateWith m s.
  Proof.
    induction s; intros; simpl in *; eauto with map_hints.
    - rewrite? updateWith_intersect_map.
      rewrite IHs1. rewrite IHs2.
      rewrite intersect_map_1234_1423.
      remember (intersect_map (updateWith m s1) (updateWith m s2)) as M.

  (*
    - apply equality_by_extends.
      +

    - f_equal.
      + f_equal.

      + transitivity (updateWith (updateWith m s1) s1); [|apply IHs1].
        apply equality_by_extends.
        * apply updateWith_monotone.

     *)

  Abort.

  Definition checker :=
    fix rec(m: map impvar srcvar)(s: astmt): option stmt' :=
      match s with
      | ASLoad x x' a =>
          bind_opt a' <- reverse_get m a;
          Some (SLoad x' a')
      | ASStore a v =>
          bind_opt a' <- reverse_get m a;
          bind_opt v' <- reverse_get m v;
          Some (SStore a' v')
      | ASLit x x' v =>
          Some (SLit x' v)
      | ASOp x x' op y z =>
          bind_opt y' <- reverse_get m y;
          bind_opt z' <- reverse_get m z;
          Some (SOp x' op y' z')
      | ASSet x x' y =>
          bind_opt y' <- reverse_get m y;
          Some (SSet x' y')
      | ASIf cond s1 s2 =>
          bind_opt cond' <- reverse_get m cond;
          bind_opt s1' <- rec m s1;
          bind_opt s2' <- rec m s2;
          Some (SIf cond' s1' s2')
      | ASLoop s1 cond s2 =>
          bind_opt cond' <- reverse_get m cond;
          let m1 := intersect_map m (updateWith m s) in
          let m2 := intersect_map (updateWith m s1) (updateWith m1 s) in
          bind_opt s1' <- rec m1 s1;
          bind_opt s2' <- rec m2 s2;
          Some (SLoop s1' cond' s2')
      | ASSeq s1 s2 =>
          bind_opt s1' <- rec m s1;
          bind_opt s2' <- rec (updateWith m s1) s2;
          Some (SSeq s1' s2')
      | ASSkip => Some SSkip
      | ASCall binds f args => None (* TODO *)
      end.

  Definition erase :=
    fix rec(s: astmt): stmt :=
      match s with
      | ASLoad x x' a => SLoad x a
      | ASStore a v => SStore a v
      | ASLit x x' v => SLit x v
      | ASOp x x' op y z => SOp x op y z
      | ASSet x x' y => SSet x y
      | ASIf cond s1 s2 => SIf cond (rec s1) (rec s2)
      | ASLoop s1 cond s2 => SLoop (rec s1) cond (rec s2)
      | ASSeq s1 s2 => SSeq (rec s1) (rec s2)
      | ASSkip => SSkip
      | ASCall binds f args => SCall (List.map fst binds) f args
      end.

  (* claim: for all astmt a, if checker succeeds and returns s', then
     (erase a) behaves the same as s' *)

  Context {mword: Set}.
  Context {MW: MachineWidth mword}.
  Context {srcStateMap: MapFunctions srcvar mword}.
  Context {impStateMap: MapFunctions impvar mword}.
  Context {srcFuncMap: MapFunctions func (list srcvar * list srcvar * stmt)}.
  Context {impFuncMap: MapFunctions func (list impvar * list impvar * stmt')}.

  Definition eval: nat -> map srcvar mword -> mem -> stmt -> option (map srcvar mword * mem)
    := eval_stmt _ _ empty_map.

  Definition eval': nat -> map impvar mword -> mem -> stmt' -> option (map impvar mword * mem)
    := eval_stmt _ _ empty_map.

  (*
  Definition states_compat(st: map srcvar mword)(r: map impvar srcvar)(st': map impvar mword) :=
    forall (x: srcvar) (w: mword),
      (* TODO restrict to live variables *)
      get st x = Some w ->
      exists (x': impvar), get r x' = Some x /\ get st' x' = Some w.
  *)

  Definition states_compat(st: map srcvar mword)(r: map impvar srcvar)(st': map impvar mword) :=
    forall (x: srcvar) (x': impvar),
      get r x' = Some x ->
      forall w,
        get st x = Some w ->
        get st' x' = Some w.

  Lemma states_compat_put: forall st1 st1' v x x' r,
      ~ x \in (range r) ->
      states_compat st1 r st1' ->
      states_compat (put st1 x v) (put r x' x) (put st1' x' v).
  Proof.
    unfold states_compat.
    intros.
    rewrite get_put.
    do 2 match goal with
    | H: get (put _ _ _) _ = _ |- _ => rewrite get_put in H
    end.
    destruct_one_match; clear E.
    - subst.
      replace x0 with x in H2 by congruence.
      destruct_one_match_hyp; [assumption|contradiction].
    - destruct_one_match_hyp.
      + subst.
        apply get_in_range in H1.
        contradiction.
      + eauto.
  Qed.

  Lemma states_compat_extends: forall st st' r1 r2,
      extends r1 r2 ->
      states_compat st r1 st' ->
      states_compat st r2 st'.
  Proof.
    unfold states_compat. eauto.
  Qed.

  Hint Resolve
       states_compat_put
       not_in_range_of_remove_by_value
       states_compat_extends
       extends_remove_by_value
       extends_intersect_map_l
       extends_intersect_map_r
    : checker_hints.

  Lemma checker_correct: forall n r st1 st1' m1 st2 m2 s annotated s',
      eval n st1 m1 s = Some (st2, m2) ->
      erase annotated = s ->
      checker r annotated = Some s' ->
      states_compat st1 r st1' ->
      exists st2',
        eval' n st1' m1 s' = Some (st2', m2) /\
        states_compat st2 (updateWith r annotated) st2'.
  Proof.
    induction n; intros; [
      match goal with
      | H: eval 0 _ _ _ = Some _ |- _ => solve [inversion H]
      end
    |].
    unfold eval, eval' in *.
    invert_eval_stmt;
      try destruct_pair_eqs;
      match goal with
      | H: erase ?s = _ |- _ =>
        destruct s;
        inversion H;
        subst;
        clear H
      end;
      subst;
      simpl in *;
      repeat (destruct_one_match_hyp; [|discriminate]);
      repeat match goal with
             | H: Some _ = Some _ |- _ => inversion H; subst; clear H
             | H: reverse_get _ _ = Some _ |- _ => apply reverse_reverse_get in H
             | H: states_compat _ _ _ |- _ => erewrite H by eassumption
             end;
      repeat match goal with
             | H: states_compat _ _ _ |- _ => erewrite H by eassumption
             | H: _ = _ |- _ => rewrite H
             end;
      repeat (rewrite reg_eqb_ne by congruence);
      repeat (rewrite reg_eqb_eq by congruence);
      eauto with checker_hints.
    - edestruct IHn as [st2' [? ?]]; [ (eassumption || reflexivity).. | ].
      eauto with checker_hints.
    - edestruct IHn as [st2' [? ?]]; [ (eassumption || reflexivity).. | ].
      eauto with checker_hints.
    - edestruct IHn as [st2' [? ?]]; eauto with checker_hints.
      rewrite H0.
      pose proof H1 as P.
      unfold states_compat in P.
      specialize P with (2 := H).
      rewrite P.
      + rewrite reg_eqb_eq by reflexivity.
        eexists; split; [ reflexivity | ].
        eapply states_compat_extends; [|eassumption].

        eauto 10 with checker_hints.
        eauto with checker_hints.


  Abort.

End RegAlloc.
