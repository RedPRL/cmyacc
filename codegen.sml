
structure Codegen
   :> CODEGEN
   =
   struct

      structure S = SymbolSet
      structure D = SymbolDict

      open Automaton

      exception Error



      fun labelToString l =
         (case l of
             Syntax.IdentLabel s =>
                Symbol.toValue s
           | Syntax.NumericLabel n =>
                Int.toString n)


      fun isUnit dom = List.null dom

      fun isSolearg dom =
         (case dom of
             [(Syntax.NumericLabel _, _)] => true
           | _ => false)

      fun isTuple dom =
         (case dom of
             (Syntax.NumericLabel _, _) :: _ :: _ => true
           | _ => false)


      (* Converts a word to a big-endian byte list. *)
      fun wordToBytelist w acc =
         if w = 0w0 then
            acc
         else
            let
               val lo = Word.andb (w, 0wxff)
               val hi = Word.>> (w, 0w8)
            in
               wordToBytelist hi (lo :: acc)
            end

      fun duplicateOnto n x acc =
         if n = 0 then
             acc
         else
            duplicateOnto (n-1) x (x :: acc)

      (* intToChars size n

         if    0 <= n < 2^(8 * size)
         then  l is a big-endian character list representing n
               |l| = stateSize
               and
               return l
      *)
      fun intToChars size n =
         let
            val l =
               map
               (fn w => Char.chr (Word.toInt w))
               (wordToBytelist (Word.fromInt n) [])
         in
            duplicateOnto (size - length l) (Char.chr 0) l
         end

      fun writeTableEntry write stateSize adjust entry =
         app
            (fn ch => write (Char.toString ch))
            (intToChars stateSize (entry + adjust))



      fun writeProgram outfile (options, types, terminals, nonterminals, actions, automaton as (stateCount, states, rules, start)) =
         let
            val functorName =
               (case D.find options (Symbol.fromValue "name") of
                   SOME name => name
                 | NONE =>
                      (
                      print "Error: no functor name specified.\n";
                      raise Error
                      ))

            val (terminalOrdinals, terminalCount) =
               D.foldl
               (fn (terminal, _, (ordinals, count)) =>
                   (D.insert ordinals terminal count,
                    count+1))
               (D.singleton (Symbol.fromValue "$") 0, 1)
               terminals

            val (nonterminalOrdinals, nonterminalCount) =
               D.foldl
               (fn (nonterminal, _, (ordinals, count)) =>
                   (D.insert ordinals nonterminal count,
                    count+1))
               (D.empty, 0)
               nonterminals

            val minorLimit = Int.max (terminalCount, nonterminalCount)
            val (minorLimit', minorSize) =
               if minorLimit <= 32 then
                  (32, "5")
               else if minorLimit <= 64 then
                  (64, "6")
               else if minorLimit <= 128 then
                  (128, "7")
               else if minorLimit <= 256 then
                  (256, "8")
               else if minorLimit <= 512 then
                  (512, "9")
               else if minorLimit = D.size terminals then
                  (
                  print "Error: too many terminals.\n";
                  raise Error
                  )
               else
                  (
                  print "Error: too many nonterminals.\n";
                  raise Error
                  )

            val majorLimit =
               Int.max (stateCount, Vector.length rules + 1)

            val (majorSize, adjust) =
               if majorLimit <= 127 then
                  (1, 128)
               else if majorLimit <= 32767 then
                  (2, 32768)
               else if majorLimit = stateCount then
                  (
                  print "Error: too many states.\n";
                  raise Error
                  )
               else
                  (
                  print "Error: too many rules.\n";
                  raise Error
                  )

            val outs = TextIO.openOut outfile
            fun write str = TextIO.output (outs, str)
         in
            write "\nfunctor ";
            write functorName;
            write "\n   (structure Streamable : STREAMABLE\n    structure Arg :\n       sig\n";

            S.app
               (fn tp =>
                   (
                   write "          type ";
                   write (Symbol.toValue tp);
                   write "\n"
                   ))
               types;

            write "\n";

            app
               (fn (action, dom, cod) =>
                   (
                   write "          val ";
                   write (Symbol.toValue action);
                   write " : ";

                   if isUnit dom then
                      write "unit"
                   else if isSolearg dom then
                      write (Symbol.toValue (#2 (hd dom)))
                   else if isTuple dom then
                      (
                      foldl
                         (fn ((_, t), first) =>
                             (* Ignore the label, because we know the list is sorted and complete. *)
                             (
                             if first then
                                ()
                             else
                                write " * ";
                             write (Symbol.toValue t);
                             false
                             ))
                         true
                         dom;
                      ()
                      )
                   else
                      (
                      write "{ ";

                      foldl
                         (fn ((l, t), first) =>
                             (
                             if first then
                                ()
                             else
                                write ", ";
                             write (labelToString l);
                             write ":";
                             write (Symbol.toValue t);
                             false
                             ))
                         true
                         dom;

                      write " }"
                      );

                   write " -> ";
                   write (Symbol.toValue cod);
                   write "\n"
                   ))
               actions;

            write "\n          datatype terminal =\n";
            D.foldl
               (fn (symbol, (tpo, _, _), first) =>
                      (
                      write "           ";
                      if first then
                         write "  "
                      else
                         write "| ";
                      write (Symbol.toValue symbol);
                      (case tpo of
                          NONE => ()
                        | SOME tp =>
                             (
                             write " of ";
                             write (Symbol.toValue tp)
                             ));
                      write "\n";
                      false
                      ))
               true
               terminals;

            write "\n          val error : terminal Streamable.t -> exn\n       end)\n   :>\n   sig\n      val parse : Arg.terminal Streamable.t -> Arg.";
            write (Symbol.toValue (#2 (D.lookup nonterminals start)));
            write " * Arg.terminal Streamable.t\n   end\n=\n\n";

            write "(*\n\n";
            WriteAutomaton.writeAutomaton outs automaton;
            write "\n*)\n\n";

            write "struct\nlocal\nstructure Value = struct\ndatatype nonterminal =\nnonterminal\n";

            S.app
               (fn tp =>
                   (
                   write "| ";
                   write (Symbol.toValue tp);
                   write " of Arg.";
                   write (Symbol.toValue tp);
                   write "\n"
                   ))
               types;

            write "end\nstructure ParseEngine = ParseEngineFun (structure Streamable = Streamable\ntype terminal = Arg.terminal\ntype value = Value.nonterminal\nval dummy = Value.nonterminal\nfun read terminal =\n(case terminal of\n";

            D.foldl
               (fn (terminal, (tpo, _, _), first) =>
                   (
                   if first then
                      ()
                   else
                      write "| ";
                   (case tpo of
                       NONE =>
                          (
                          write "Arg.";
                          write (Symbol.toValue terminal);
                          write " => (";
                          write (Int.toString (D.lookup terminalOrdinals terminal));
                          write ", Value.nonterminal)\n"
                          )
                     | SOME tp =>
                          (
                          write "Arg.";
                          write (Symbol.toValue terminal);
                          write " x => (";
                          write (Int.toString (D.lookup terminalOrdinals terminal));
                          write ", Value.";
                          write (Symbol.toValue tp);
                          write " x)\n"
                          ));
                   false
                   ))
            true
            terminals;

            write ")\n)\nin\nval parse = ParseEngine.parse (\nParseEngine.next";
            write minorSize;
            write "x";
            write (Int.toString majorSize);
            write " \"";

            app
               (fn (d, _, _) =>
                   let
                      val arr =
                         (* initialize with 0, which represents error *)
                         Array.array (minorLimit', 0)
                   in
                      D.app
                         (fn (terminal, (Shift n :: _, _)) =>
                                Array.update (arr, D.lookup terminalOrdinals terminal, n+1)
                           | (terminal, (Reduce n :: _, _)) =>
                                (* When n = ~1, this is the accept action. *)
                                Array.update (arr, D.lookup terminalOrdinals terminal, ~(n+2))
                           | _ =>
                                raise (Fail "invariant"))
                         d;

                      Array.app (writeTableEntry write majorSize adjust) arr
                   end)
               states;

            write "\",\nParseEngine.next";
            write minorSize;
            write "x";
            write (Int.toString majorSize);
            write " \"";

            app
               (fn (_, d, _) =>
                   let
                      val arr =
                         Array.array (minorLimit', 0)
                   in
                      D.app
                         (fn (nonterminal, n) =>
                             Array.update (arr, D.lookup nonterminalOrdinals nonterminal, n))
                         d;

                      Array.app (writeTableEntry write majorSize adjust) arr
                   end)
               states;

            write "\",\nVector.fromList [";

            Vector.foldl
               (fn ((rulenum, _, lhs, rhs, args, solearg, action, _, _), first) =>
                   (
                   if first then
                      ()
                   else
                      write ",\n";
                   write "(";
                   write (Int.toString (D.lookup nonterminalOrdinals lhs));
                   write ",";
                   write (Int.toString (length rhs));
                   write ",(fn ";

                   ListPair.foldrEq
                      (fn (_, NONE, n) =>
                             (
                             write "_::";
                             n
                             )
                        | (symbol, SOME label, n) =>
                             let
                                val tp =
                                   (case D.find nonterminals symbol of
                                       SOME (_, tp, _) => tp
                                     | NONE =>
                                          valOf (#1 (D.lookup terminals symbol)))
                             in
                                write "Value.";
                                write (Symbol.toValue tp);
                                write "(arg";
                                write (Int.toString n);
                                write ")::";
                                n+1
                             end)
                      0
                      (rhs, args);

                   write "rest => Value.";
                   write (Symbol.toValue (#2 (D.lookup nonterminals lhs)));
                   write "(Arg.";
                   write (Symbol.toValue action);
                   write " ";

                   (* If solearg, we suppress generating a record pattern. *)
                   if solearg then
                      write "arg0"
                   else
                      (
                      write "{";

                      foldr
                         (fn (NONE, n) => n
                           | (SOME label, n) =>
                                (
                                if n = 0 then
                                   ()
                                else
                                   write ",";
                                write (labelToString label);
                                write "=arg";
                                write (Int.toString n);
                                n+1
                                ))
                         0
                         args;

                      write "}"
                      );

                   write ")::rest";
                   if List.null rhs then
                      ()
                   else
                      write "|_=>raise (Fail \"bad parser\")";
                   write "))";
                   false
                   ))
               true
               rules;

            write "],\n(fn Value.";
            write (Symbol.toValue (#2 (D.lookup nonterminals start)));
            write " x => x | _ => raise (Fail \"bad parser\")), Arg.error)\nend\nend\n";

            TextIO.closeOut outs
         end

   end
