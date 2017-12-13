Require Import Coq.Lists.List.
Import ListNotations.
Require Import Coq.Arith.PeanoNat.
Require Import compiler.Decidable.
Require Import compiler.Op.
Require Import compiler.member.
Require Import compiler.For.

(* Note: you can't ask an array for its length *)
Class IsArray(T E: Type) := mkIsArray {
  defaultElem: E;
  get: T -> nat -> E;
  update: T -> nat -> E -> T;
  newArray: nat -> T
}.

Definition listUpdate{E: Type}(l: list E)(i: nat)(e: E): list E :=
  firstn i l ++ [e] ++ skipn (S i) l.

Definition listFill{E: Type}(e: E): nat -> list E :=
  fix rec(n: nat) := match n with
  | O => nil
  | S m => e :: rec m
  end.

Instance ListIsArray: forall (T: Type) (d: T), IsArray (list T) T := fun T d => {|
  defaultElem := d;
  get := fun l i => nth i l d;
  update := listUpdate;
  newArray := listFill d
|}.


(* Low-Level Gallina *)
Section LLG.

  Context {var: Set}.
  Context {eq_var_dec: DecidableEq var}.

  (* isomorphic to nat *)
  Inductive type: Set :=
  | TNat: type
  | TArray: type -> type.

  Definition extend{l}(G: member l -> type)(x: var)(t: type): member (x :: l) -> type :=
    fun m => match m with (* (fancy return clause inferred) *)
    | member_here _ _ => fun _ => t
    | member_there _ _ m' => fun G => G m'
    end G.

  Inductive expr: forall l: list var, (member l -> type) -> type -> Set :=
  | ELit{l G}(v: nat): expr l G TNat
  | EVar{l G}(m: member l): expr l G (G m)
  | EOp{l G}(e1: expr l G TNat)(op: binop)(e2: expr l G TNat): expr l G TNat
  | ELet{l G t1 t2}(x: var)(e1: expr l G t1)(e2: expr (x :: l) (extend G x t1) t2): expr l G t2
  | ENewArray{l G}(t: type)(size: expr l G TNat): expr l G (TArray t)
  | EGet{l G t}(a: expr l G (TArray t))(i: expr l G TNat): expr l G t
  | EUpdate{l G t}(a: expr l G (TArray t))(i: expr l G TNat)(v: expr l G t): expr l G (TArray t)
  (* TODO allow several updated vars *)
  | EFor{l G t}(i: var)(to: expr l G TNat)(updates: member l)
      (body: expr (i :: l) (extend G i TNat) (G updates))
      (rest: expr l G t):
      expr l G t.

  Definition interp_type: type -> Type :=
    fix rec(t: type): Type := match t with
    | TNat => nat
    | TArray t' => list (rec t')
    end.

  Definition interp_type_IsArray(t: type): IsArray (list (interp_type t)) (interp_type t) :=
    match t with
    | TNat => ListIsArray nat 0
    | TArray _ => ListIsArray _ nil
    end.

  Definition extend_vals:
    forall {l} (G: member l -> type)(vals: forall m: member l, interp_type (G m))
    (x: var)(t: type)(v: interp_type t),
    forall m: member (x :: l), interp_type (extend G x t m).
    intros.
    apply (destruct_member m).
    - intro E. subst m. simpl. exact v.
    - intros m' E. subst m. simpl. exact (vals m').
  Defined.

  Definition update_vals(l: list var)(G: member l -> type)(i: member l)(v: interp_type (G i))
    (vals: forall m: member l, interp_type (G m)):
           forall m: member l, interp_type (G m).
    intro m.
    destruct (eq_member_dec _ i m).
    - rewrite <- e. exact v.
    - exact (vals m).
  Defined.

  Definition interp_expr:
    forall {l G t}(e: expr l G t)(vals: forall x: member l, interp_type (G x)), interp_type t :=
    fix rec l G t (e: expr l G t) {struct e} :=
      match e in (expr l G t) return ((forall x: member l, interp_type (G x)) -> interp_type t) with
      | ELit v => fun vals => v
      | EVar m => fun vals => vals m
      | EOp e1 op e2 => fun vals => eval_binop_nat op (rec _ _ _ e1 vals) (rec _ _ _ e2 vals)
      | @ELet l G t1 t2 x e1 e2 => fun vals =>
          let r1 := rec _ _ _ e1 vals in
          let vals' := extend_vals G vals x t1 r1 in
          rec _ _ _ e2 vals'
      | @ENewArray l G t size => fun vals =>
          let size1 := rec _ _ _ size vals in
          @newArray _ _ (interp_type_IsArray t) size1
      | @EGet l G t a i => fun vals =>
          let a1 := rec _ _ _ a vals in
          let i1 := rec _ _ _ i vals in
          @get _ _ (interp_type_IsArray t) a1 i1
      | @EUpdate l G t a i v => fun vals =>
          let a1 := rec _ _ _ a vals in
          let i1 := rec _ _ _ i vals in
          let v1 := rec _ _ _ v vals in
          @update _ _ (interp_type_IsArray t) a1 i1 v1
      | @EFor l G t i to updates body rest => fun vals =>
          let to1 := rec _ _ _ to vals in
          let bodyFun := rec _ _ _ body in
          let s1 := (fix f(n: nat) := match n with
                     | 0 => vals updates
                     | S m => let s1 := f m in
                         let vals' := update_vals _ _ updates s1 vals in
                         let vals'' := extend_vals G vals' i TNat m in
                         bodyFun vals''
                     end) to1 in
          let vals' := update_vals _ _ updates s1 vals in
          rec _ _ _ rest vals'
      end.

End LLG.

Module LLG_Tests.

Definition test1(v1 v2: nat): nat := let x1 := v1 in let x2 := v2 in x1.

Definition myvar := nat.
Definition var_x1: myvar := 1.
Definition var_x2: myvar := 2.
Definition var_i: myvar := 3.

Definition empty_types: member (@nil myvar) -> type. intro. inversion H. Defined.
Definition empty_vals: forall m : member (@nil myvar), interp_type (empty_types m).
  intro. inversion m. Defined.

Definition x1_in_x2x1: member [var_x2; var_x1]. apply member_there. apply member_here. Defined.
Definition x2_in_x2x1: member [var_x2; var_x1]. apply member_here. Defined.

Definition test1a(v1 v2: nat): expr (@nil myvar) empty_types TNat :=
  ELet var_x1 (ELit v1) (ELet var_x2 (ELit v2) (EVar x1_in_x2x1)).

Definition interp_expr'{t}(e: expr (@nil myvar) empty_types t): interp_type t :=
  interp_expr e empty_vals.

Goal forall v1 v2, test1 v1 v2 = interp_expr' (test1a v1 v2).
  intros. reflexivity.
Qed.

Definition ListWithDefault0IsArray := ListIsArray nat 0.
Existing Instance ListWithDefault0IsArray.

Definition test2(i v: nat): nat :=
  let x1 := newArray 3 in
  let x2 := update x1 i v in
  get x2 i.

Definition x1_in_x1: member [var_x1]. apply member_here. Defined.

Definition test2a(i v: nat): expr (@nil myvar) empty_types TNat :=
  ELet var_x1 (ENewArray TNat (ELit 3))
  (ELet var_x2 (EUpdate (EVar x1_in_x1) (ELit i) (ELit v))
  (EGet (EVar x2_in_x2x1) (ELit i))).

Goal forall i v, test2 i v = interp_expr' (test2a i v).
  intros. reflexivity.
Qed.

Definition test3(n: nat): list nat :=
  let x1 := newArray n in
  for i from 0 to n updating (x1) {{
     update x1 i (i * i)
  }} ;;
  x1.

Goal test3 4 = [0; 1; 4; 9]. reflexivity. Qed.

Definition x1_in_ix1: member [var_i; var_x1]. apply member_there. apply member_here. Defined.
Definition i_in_ix1: member [var_i; var_x1]. apply member_here. Defined.

Definition test3a(n: nat): expr (@nil myvar) empty_types (TArray TNat) :=
  ELet var_x1 (ENewArray TNat (ELit n))
  (EFor var_i (ELit n) x1_in_x1
     (EUpdate (EVar x1_in_ix1) (EVar i_in_ix1) (EOp (EVar i_in_ix1) OTimes (EVar i_in_ix1)))
   (EVar x1_in_x1)).

Goal test3 5 = interp_expr' (test3a 5). cbv. reflexivity. Qed.

Goal forall n, test3 n = interp_expr' (test3a n). intros. reflexivity. Qed.

End LLG_Tests.
