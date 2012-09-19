/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-CurrentYear, Linköping University,
 * Department of Computer and Information Science,
 * SE-58183 Linköping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF GPL VERSION 3 
 * AND THIS OSMC PUBLIC LICENSE (OSMC-PL). 
 * ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES RECIPIENT'S  
 * ACCEPTANCE OF THE OSMC PUBLIC LICENSE.
 *
 * The OpenModelica software and the Open Source Modelica
 * Consortium (OSMC) Public License (OSMC-PL) are obtained
 * from Linköping University, either from the above address,
 * from the URLs: http://www.ida.liu.se/projects/OpenModelica or  
 * http://www.openmodelica.org, and in the OpenModelica distribution. 
 * GNU version 3 is obtained from: http://www.gnu.org/copyleft/gpl.html.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without
 * even the implied warranty of  MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
 * IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS
 * OF OSMC-PL.
 *
 * See the full OSMC Public License conditions for more details.
 *
 */

encapsulated package BackendDAETransform
" file:        BackendDAETransform.mo
  package:     BackendDAETransform
  description: BackendDAETransform contains functions that are needed to perform 
               a transformation to a Block-Lower-Triangular-DAE.
               - matchingAlgorithm
               - strongComponents
               - reduceIndexDummyDer

  
  RCS: $Id$
"

public import Absyn;
public import BackendDAE;
public import DAE;
public import Env;
public import HashTable3;
public import HashTableCG;

protected import BackendDAEEXT;
protected import BackendDAEUtil;
protected import BackendDump;
protected import BackendEquation;
protected import BackendVariable;
protected import BaseHashTable;
protected import ComponentReference;
protected import DAEUtil;
protected import Debug;
protected import Derive;
protected import Error;
protected import Expression;
protected import ExpressionDump;
protected import Flags;
protected import List;
protected import SCode;
protected import Util;
protected import Values;

/******************************************
 matchingAlgorithm and stuff
 *****************************************/

public function matchingAlgorithm
"function: matchingAlgorithm
  author: PA
  This function performs the matching algorithm, which is the first
  part of sorting the equations into BLT (Block Lower Triangular) form.
  The matching algorithm finds a variable that is solved in each equation.
  But to also find out which equations forms a block of equations, the
  the second algorithm of the BLT sorting: strong components
  algorithm is run.
  This function returns the updated DAE in case of index reduction has
  added equations and variables, and the incidence matrix. The variable
  assignments is returned as a vector of variable indices, as well as its
  inverse, i.e. which equation a variable is solved in as a vector of
  equation indices.
  BackendDAE.MatchingOptions contain options given to the algorithm.
    - if index reduction should be used or not.
    - if the equation system is allowed to be under constrained or not
      which is used when generating code for initial equations.
  
  inputs:  (BackendDAE,IncidenceMatrix, BackendDAE.IncidenceMatrixT, MatchingOptions)
  outputs: (int vector /* vector of equation indices */ ,
              int vector /* vector of variable indices */,
              BackendDAE,IncidenceMatrix, IncidenceMatrixT)"
  input BackendDAE.EqSystem isyst;
  input BackendDAE.Shared ishared;
  input BackendDAE.MatchingOptions inMatchingOptions;
  input StructurallySingularSystemHandlerFunc sssHandler;
  input BackendDAE.StructurallySingularSystemHandlerArg inArg; 
  output BackendDAE.EqSystem osyst;
  output BackendDAE.Shared oshared;
  output BackendDAE.StructurallySingularSystemHandlerArg outArg;  
  partial function StructurallySingularSystemHandlerFunc
    input list<Integer> eqns;
    input Integer actualEqn;
    input BackendDAE.EqSystem isyst;
    input BackendDAE.Shared ishared;
    input array<Integer> inAssignments1;
    input array<Integer> inAssignments2;
    input BackendDAE.StructurallySingularSystemHandlerArg inArg;
    output list<Integer> changedEqns;
    output Integer continueEqn;
    output BackendDAE.EqSystem osyst;
    output BackendDAE.Shared oshared;
    output array<Integer> outAssignments1;
    output array<Integer> outAssignments2; 
    output BackendDAE.StructurallySingularSystemHandlerArg outArg;
  end StructurallySingularSystemHandlerFunc;   
algorithm
  (osyst,oshared,outArg) :=
  matchcontinue (isyst,ishared,inMatchingOptions,sssHandler,inArg)
    local
      Integer nvars,neqns,memsize;
      BackendDAE.Assignments assign1,assign2,ass1,ass2;
      BackendDAE.IncidenceMatrix m;
      BackendDAE.IncidenceMatrixT mt;      
      array<Integer> vec1,vec2;
      BackendDAE.StructurallySingularSystemHandlerArg arg;
      BackendDAE.EquationArray eqs;
      BackendDAE.Variables vars;
      BackendDAE.EqSystem syst;
      BackendDAE.Shared shared;

    // fail case if daelow is empty
    case (syst as BackendDAE.EQSYSTEM(vars,eqs,SOME(m),SOME(mt),_),_,_,_,_)
      equation
        nvars = arrayLength(m);
        neqns = arrayLength(mt);
        (nvars == 0) = true;
        (neqns == 0) = true;
        vec1 = listArray({});
        vec2 = listArray({});
      then
        (BackendDAE.EQSYSTEM(vars,eqs,SOME(m),SOME(mt),BackendDAE.MATCHING(vec1,vec2,{})),ishared,inArg);
    case (syst as BackendDAE.EQSYSTEM(vars,eqs,SOME(m),SOME(mt),_),_,_,_,_)
      equation
        BackendDAEEXT.clearDifferentiated();
        checkMatching(syst, inMatchingOptions);
        nvars = arrayLength(m);
        neqns = arrayLength(mt);
        (nvars > 0) = true;
        (neqns > 0) = true;
        memsize = nvars + nvars "Worst case, all eqns are differentiated once. Create nvars2 assignment elements" ;
        assign1 = assignmentsCreate(nvars, memsize, 0);
        assign2 = assignmentsCreate(nvars, memsize, 0);
        (ass1,ass2,syst as BackendDAE.EQSYSTEM(orderedVars=vars,orderedEqs=eqs,m=SOME(m),mT=SOME(mt)),shared,arg) = 
          matchingAlgorithm2(syst,ishared,nvars, neqns, 1, assign1, assign2, inMatchingOptions, sssHandler, inArg);
        vec1 = assignmentsVector(ass1);
        vec2 = assignmentsVector(ass2);
      then
        (BackendDAE.EQSYSTEM(vars,eqs,SOME(m),SOME(mt),BackendDAE.MATCHING(vec1,vec2,{})),shared,arg);

    else
      equation
        Debug.fprint(Flags.FAILTRACE, "- BackendDAE.MatchingAlgorithm failed\n");
      then
        fail();
  end matchcontinue;
end matchingAlgorithm;

public function checkMatching
"function: checkMatching
  author: PA

  Checks that the matching is correct, i.e. that the number of variables
  is the same as the number of equations. If not, the function fails and
  prints an error message.
  If matching options indicate that underconstrained systems are ok, no
  check is performed."
  input BackendDAE.EqSystem syst;
  input BackendDAE.MatchingOptions inMatchingOptions;
algorithm
  _ := matchcontinue (syst,inMatchingOptions)
    local
      Integer esize,vars_size;
      BackendDAE.EquationArray eqns;
      BackendDAE.Variables vars;
      String esize_str,vsize_str;
    case (_,(_,BackendDAE.ALLOW_UNDERCONSTRAINED())) then ();
    case (BackendDAE.EQSYSTEM(orderedVars = vars,orderedEqs = eqns),_)
      equation
        vars_size = BackendVariable.varsSize(vars);
        esize = BackendDAEUtil.equationSize(eqns);
        ((esize) == vars_size) = true;
      then
        ();
    case (BackendDAE.EQSYSTEM(orderedVars = vars,orderedEqs = eqns),_)
      equation
        vars_size = BackendVariable.varsSize(vars);
        esize = BackendDAEUtil.equationSize(eqns);
        (esize < vars_size) = true;
        esize = esize - 1;
        vars_size = vars_size - 1 "remove dummy var" ;
        esize_str = intString(esize) "remove dummy var" ;
        vsize_str = intString(vars_size);
        Error.addMessage(Error.UNDERDET_EQN_SYSTEM, {esize_str,vsize_str});
      then
        fail();
    case (BackendDAE.EQSYSTEM(orderedVars = vars,orderedEqs = eqns),_)
      equation
        vars_size = BackendVariable.varsSize(vars);
        esize = BackendDAEUtil.equationSize(eqns);
        (esize > vars_size) = true;
        esize = esize - 1;
        vars_size = vars_size - 1 "remove dummy var" ;
        esize_str = intString(esize) "remove dummy var" ;
        vsize_str = intString(vars_size);
        Error.addMessage(Error.OVERDET_EQN_SYSTEM, {esize_str,vsize_str});
      then
        fail();
    else
      equation
        Debug.fprint(Flags.FAILTRACE, "- BackendDAETransform.checkMatching failed\n");
      then
        fail();
  end matchcontinue;
end checkMatching;

protected function assignmentsVector
"function: assignmentsVector
  author: PA
  Converts BackendDAE.Assignments to vector of int elements"
  input BackendDAE.Assignments inAssignments;
  output array<Integer> outIntegerArray;
algorithm
  outIntegerArray := matchcontinue (inAssignments)
    local
      array<Integer> newarr,newarr_1,arr;
      array<Integer> vec;
      Integer size;
    case (BackendDAE.ASSIGNMENTS(actualSize = size,arrOfIndices = arr))
      equation
        newarr = arrayCreate(size, 0);
        newarr_1 = Util.arrayNCopy(arr, newarr, size);
        vec = arrayCopy(newarr_1);
      then
        vec;
    case (_)
      equation
        Error.addMessage(Error.INTERNAL_ERROR, {"- BackendDAETransform.assignmentsVector failed!"});
      then
        fail();
  end matchcontinue;
end assignmentsVector;

protected function assignmentsCreate
"function: assignmentsCreate
  author: PA
  Creates an assignment array of n elements, filled with value v
  inputs:  (int /* size */, int /* memsize */, int)
  outputs: => Assignments"
  input Integer n;
  input Integer memsize;
  input Integer v;
  output BackendDAE.Assignments outAssignments;
protected
  list<Integer> lst;
  array<Integer> arr;
algorithm
  arr := arrayCreate(memsize, 0);
  outAssignments := BackendDAE.ASSIGNMENTS(n,memsize,arr);
end assignmentsCreate;

protected function assignmentsSetnth
"function: assignmentsSetnth
  author: PA
  Sets the n:nt assignment Value.
  inputs:  (Assignments, int /* n */, int /* value */)
  outputs:  Assignments"
  input BackendDAE.Assignments inAssignments1;
  input Integer n;
  input Integer v;
  output BackendDAE.Assignments outAssignments;
algorithm
  outAssignments := matchcontinue (inAssignments1,n,v)
    local
      array<Integer> arr;
      Integer s,ms;
    case (BackendDAE.ASSIGNMENTS(actualSize = s,allocatedSize = ms,arrOfIndices = arr),_,_)
      equation
        arr = arrayUpdate(arr, n, v);
      then
        BackendDAE.ASSIGNMENTS(s,ms,arr);
    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR, {"- BackendDAETransform.assignments_setnth failed!"});
      then
        fail();
  end matchcontinue;
end assignmentsSetnth;

protected function assignmentsExpand
"function: assignmentsExpand
  author: PA
  Expands the assignments array with n values, initialized with zero.
  inputs:  (Assignments, int /* n */)
  outputs:  Assignments"
  input BackendDAE.Assignments inAssignments;
  input Integer n;
  output BackendDAE.Assignments outAssignments;
algorithm
  outAssignments := matchcontinue (inAssignments,n)
    local
      BackendDAE.Assignments ass,ass_1,ass_2;
      Integer n_1;
    case (ass,0) then ass;
    case (ass,_)
      equation
        true = n > 0;
        ass_1 = assignmentsAdd(ass, -1);
        n_1 = n - 1;
        ass_2 = assignmentsExpand(ass_1, n_1);
      then
        ass_2;
    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR, {"- BackendDAETransform.assignmentsExpand: n should not be negative!"});
      then
        fail();
  end matchcontinue;
end assignmentsExpand;

protected function assignmentsAdd
"function: assignmentsAdd
  author: PA
  Adds a value to the end of the assignments array. If memsize = actual size
  this means copying the whole array, expanding it size to fit the value
  Expansion is made by a factor 1.4. Otherwise, the element is inserted taking O(1) in
  insertion cost.
  inputs:  (Assignments, int /* value */)
  outputs:  Assignments"
  input BackendDAE.Assignments inAssignments;
  input Integer v;
  output BackendDAE.Assignments outAssignments;
algorithm
  outAssignments := matchcontinue (inAssignments,v)
    local
      Real msr,msr_1;
      Integer ms_1,s_1,ms_2,s,ms;
      array<Integer> arr_1,arr_2,arr;

    case (BackendDAE.ASSIGNMENTS(actualSize = s,allocatedSize = ms,arrOfIndices = arr),_)
      equation
        (s == ms) = true "Out of bounds, increase and copy." ;
        msr = intReal(ms);
        msr_1 = msr *. 0.4;
        ms_1 = realInt(msr_1);
        s_1 = s + 1;
        ms_2 = ms_1 + ms;
        arr_1 = Util.arrayExpand(ms_1, arr, -1);
        arr_2 = arrayUpdate(arr_1, s + 1, v);
      then
        BackendDAE.ASSIGNMENTS(s_1,ms_2,arr_2);

    case (BackendDAE.ASSIGNMENTS(actualSize = s,allocatedSize = ms,arrOfIndices = arr),_)
      equation
        arr_1 = arrayUpdate(arr, s + 1, v) "space available, increase size and insert element." ;
        s_1 = s + 1;
      then
        BackendDAE.ASSIGNMENTS(s_1,ms,arr_1);

    case (BackendDAE.ASSIGNMENTS(actualSize = s,allocatedSize = ms,arrOfIndices = arr),_)
      equation
        Error.addMessage(Error.INTERNAL_ERROR, {"-BackendDAETranfrom.assignmentsAdd failed!"});
      then
        fail();
  end matchcontinue;
end assignmentsAdd;

public function matchingAlgorithm2
"function: matchingAlgorithm2
  author: PA
  This is the outer loop of the matching algorithm
  The find_path algorithm is called for each equation/variable.
  inputs:  (BackendDAE,IncidenceMatrix, IncidenceMatrixT
             ,int /* number of vars */
             ,int /* number of eqns */
             ,int /* current var */
             ,Assignments  /* assignments, array of eqn indices */
             ,Assignments /* assignments, array of var indices */
             ,MatchingOptions) /* options for matching alg. */
  outputs: (Assignments, /* assignments, array of equation indices */
              Assignments, /* assignments, list of variable indices */
              BackendDAE, BackendDAE.IncidenceMatrix, IncidenceMatrixT)"
  input BackendDAE.EqSystem isyst;
  input BackendDAE.Shared ishared;
  input Integer nv;
  input Integer nf;
  input Integer i;
  input BackendDAE.Assignments ass1;
  input BackendDAE.Assignments ass2;
  input BackendDAE.MatchingOptions inMatchingOptions9;
  input StructurallySingularSystemHandlerFunc sssHandler;
  input BackendDAE.StructurallySingularSystemHandlerArg inArg;
  output BackendDAE.Assignments outAssignments1;
  output BackendDAE.Assignments outAssignments2;
  output BackendDAE.EqSystem osyst;
  output BackendDAE.Shared oshared;
  output BackendDAE.StructurallySingularSystemHandlerArg outArg;
  partial function StructurallySingularSystemHandlerFunc
    input list<Integer> eqns;
    input Integer actualEqn;
    input BackendDAE.EqSystem isyst;
    input BackendDAE.Shared ishared;
    input array<Integer> inAssignments1;
    input array<Integer> inAssignments2;
    input BackendDAE.StructurallySingularSystemHandlerArg inArg;
    output list<Integer> changedEqns;
    output Integer continueEqn;
    output BackendDAE.EqSystem osyst;
    output BackendDAE.Shared oshared;
    output array<Integer> outAssignments1;
    output array<Integer> outAssignments2; 
    output BackendDAE.StructurallySingularSystemHandlerArg outArg;
  end StructurallySingularSystemHandlerFunc;   
algorithm
  (outAssignments1,outAssignments2,osyst,oshared,outArg):=
  matchcontinue (isyst,ishared,nv,nf,i,ass1,ass2,inMatchingOptions9,sssHandler,inArg)
    local
      BackendDAE.Assignments ass1_1,ass2_1,ass1_2,ass2_2,ass1_3,ass2_3;
      BackendDAE.IncidenceMatrix m;
      BackendDAE.IncidenceMatrixT mt;
      Integer i_1,nv_1,nf_1,nvd,an1,am1,an2,am2;
      BackendDAE.MatchingOptions match_opts;
      BackendDAE.EquationArray eqnsarr;
      BackendDAE.EquationConstraints eq_cons;
      list<Integer> eqn_lst,var_lst,meqns;
      String eqn_str,var_str;
      BackendDAE.StructurallySingularSystemHandlerArg arg,arg1;
      DAE.ElementSource source;
      Absyn.Info info;
      BackendDAE.EqSystem syst;
      BackendDAE.Shared shared;      
      array<Integer> vec1,vec2;

    case (syst as BackendDAE.EQSYSTEM(m=SOME(m),mT=SOME(mt)),_,_,_,_,_,_,_,_,_)
      equation
        true = intGe(i,nv);
        BackendDAEEXT.initMarks(nv, nf);
        (ass1_1,ass2_1) = pathFound(m, mt, i, ass1, ass2) "eMark(i)=vMark(i)=false; eMark(i)=vMark(i)=false exit loop";
      then
        (ass1_1,ass2_1,syst,ishared,inArg);

    case (syst as BackendDAE.EQSYSTEM(m=SOME(m),mT=SOME(mt)),_,_,_,_,_,_,_,_,_)
      equation
        i_1 = i + 1;
        BackendDAEEXT.initMarks(nv, nf);
        (ass1_1,ass2_1) = pathFound(m, mt, i, ass1, ass2) "eMark(i)=vMark(i)=false" ;
        (ass1_2,ass2_2,syst,shared,arg) = matchingAlgorithm2(syst, ishared, nv, nf, i_1, ass1_1, ass2_1, inMatchingOptions9, sssHandler, inArg);
      then
        (ass1_2,ass2_2,syst,shared,arg);

    case (_,_,_,_,_,BackendDAE.ASSIGNMENTS(an1,am1,vec1),BackendDAE.ASSIGNMENTS(an2,am2,vec2),match_opts as (BackendDAE.INDEX_REDUCTION(),eq_cons),_,_)
      equation
        meqns = BackendDAEEXT.getMarkedEqns();
        (_,i_1,syst,shared,vec1,vec2,arg) = sssHandler(meqns,i,isyst,ishared,vec1,vec2,inArg)
        "path_found failed, Try index reduction using dummy derivatives.
         When a constraint exist between states and index reduction is needed
         the dummy derivative will select one of the states as a dummy state
         (and the derivative of that state as a dummy derivative).
         For instance, u1=u2 is a constraint between states. Choose u1 as dummy state
         and der(u1) as dummy derivative, named der_u1. The differentiated function
         then becomes: der_u1 = der(u2).
         In the dummy derivative method this equation is added and the original equation
         u1=u2 is kept. This is not the case for the original pantilides algorithm, where
         the original equation is removed from the system." ;
        ass1_1 = BackendDAE.ASSIGNMENTS(an1,am1,vec1); 
        ass2_1 = BackendDAE.ASSIGNMENTS(an2,am2,vec2); 
        eqnsarr = BackendEquation.daeEqns(syst);
        nf_1 = BackendDAEUtil.equationSize(eqnsarr) "and try again, restarting. This could be optimized later. It should not
                                   be necessary to restart the matching, according to Bernard Bachmann. Instead one
                                   could continue the matching as usual. This was tested (2004-11-22) and it does not
                                   work to continue without restarting.
                                   For instance the Influenca model \"../testsuite/mofiles/Influenca.mo\" does not work if
                                   not restarting.
                                   2004-12-29 PA. This was a bug, assignment lists needed to be expanded with the size
                                   of the system in order to work. SO: Matching is not needed to be restarted from
                                   scratch." ;
        nv_1 = BackendVariable.varsSize(BackendVariable.daeVars(syst));
        nvd = nv_1 - nv;
        ass1_2 = assignmentsExpand(ass1_1, nvd);
        ass2_2 = assignmentsExpand(ass2_1, nvd);
        (ass1_3,ass2_3,syst,shared,arg1) = matchingAlgorithm2(syst,shared,nv_1,nf_1,i_1,ass1_2,ass2_2,match_opts,sssHandler,arg);
      then
        (ass1_3,ass2_3,syst,shared,arg1);

    else
      equation
        eqn_lst = BackendDAEEXT.getMarkedEqns() "When index reduction also fails, the model is structurally singular." ;
        var_lst = BackendDAEEXT.getMarkedVariables();
        eqn_str = BackendDump.dumpMarkedEqns(isyst, eqn_lst);
        var_str = BackendDump.dumpMarkedVars(isyst, var_lst);
        i_1::_ = eqn_lst;
        source = BackendEquation.markedEquationSource(isyst, i_1);
        info = DAEUtil.getElementSourceFileInfo(source);
        Error.addSourceMessage(Error.STRUCT_SINGULAR_SYSTEM, {eqn_str,var_str}, info);
        //print("structurally singular. IM:");
        //dumpIncidenceMatrix(m);
        //print("daelow:");
        //dump(dae);
      then
        fail();

  end matchcontinue;
end matchingAlgorithm2;

protected function pathFound "function: pathFound
  author: PA
  This function is part of the matching algorithm.
  It tries to find a matching for the equation index given as
  third argument, i.
  inputs:  (IncidenceMatrix, BackendDAE.IncidenceMatrixT, int /* equation */,
               Assignments, Assignments)
  outputs: (Assignments, Assignments)"
  input BackendDAE.IncidenceMatrix m;
  input BackendDAE.IncidenceMatrixT mt;
  input Integer i;
  input BackendDAE.Assignments ass1;
  input BackendDAE.Assignments ass2;
  output BackendDAE.Assignments outAssignments1;
  output BackendDAE.Assignments outAssignments2;
algorithm
  (outAssignments1,outAssignments2):=
  matchcontinue (m,mt,i,ass1,ass2)
    local
      BackendDAE.Assignments ass1_1,ass2_1;
    case (_,_,_,_,_)
      equation
        BackendDAEEXT.eMark(i) "Side effect" ;
        (ass1_1,ass2_1) = assignOneInEqn(m, mt, i, ass1, ass2);
      then
        (ass1_1,ass2_1);
    case (_,_,_,_,_)
      equation
        (ass1_1,ass2_1) = forallUnmarkedVarsInEqn(m, mt, i, ass1, ass2);
      then
        (ass1_1,ass2_1);
  end matchcontinue;
end pathFound;

protected function assignOneInEqn "function: assignOneInEqn
  author: PA
  Helper function to pathFound."
  input BackendDAE.IncidenceMatrix m;
  input BackendDAE.IncidenceMatrixT mt;
  input Integer i;
  input BackendDAE.Assignments ass1;
  input BackendDAE.Assignments ass2;
  output BackendDAE.Assignments outAssignments1;
  output BackendDAE.Assignments outAssignments2;
protected
  list<Integer> vars;
algorithm
  vars := BackendDAEUtil.varsInEqn(m, i);
  (outAssignments1,outAssignments2):= assignFirstUnassigned(i, vars, ass1, ass2);
end assignOneInEqn;

protected function assignFirstUnassigned
"function: assignFirstUnassigned
  author: PA
  This function assigns the first unassign variable to the equation
  given as first argument. It is part of the matching algorithm.
  inputs:  (int /* equation */,
            int list /* variables */,
            BackendDAE.Assignments /* ass1 */,
            BackendDAE.Assignments /* ass2 */)
  outputs: (Assignments,  /* ass1 */
            Assignments)  /* ass2 */"
  input Integer i;
  input list<Integer> inIntegerLst2;
  input BackendDAE.Assignments ass1;
  input BackendDAE.Assignments ass2;
  output BackendDAE.Assignments outAssignments1;
  output BackendDAE.Assignments outAssignments2;
algorithm
  (outAssignments1,outAssignments2):=
  matchcontinue (i,inIntegerLst2,ass1,ass2)
    local
      BackendDAE.Assignments ass1_1,ass2_1;
      Integer v;
      list<Integer> vs;
    case (_,(v :: vs),_,_)
      equation
        false = intGt(getAssigned(v, ass1),0);
        (ass1_1,ass2_1) = assign(v, i, ass1, ass2);
      then
        (ass1_1,ass2_1);
    case (_,(v :: vs),_,_)
      equation
        (ass1_1,ass2_1) = assignFirstUnassigned(i, vs, ass1, ass2);
      then
        (ass1_1,ass2_1);
  end matchcontinue;
end assignFirstUnassigned;

public function getAssigned
"function: getAssigned
  author: PA
  returns the assigned equation/variable for a variable/equation.
  inputs:  (int    /* variable/equation */,
            Assignments,  /* ass */
  outputs:  int /* equation/variable */"
  input Integer inInteger1;
  input BackendDAE.Assignments inAssignments;
  output Integer outInteger;
algorithm
  outInteger:=
  match (inInteger1,inAssignments)
    local
      array<Integer> m;
    case (_,BackendDAE.ASSIGNMENTS(arrOfIndices = m)) then m[inInteger1];
  end match;
end getAssigned;

protected function assign
"function: assign
  author: PA
  Assign a variable to an equation, updating both assignment lists.
  inputs: (int, /* variable */
           int, /* equation */
           Assignments, /* ass1 */
           Assignments) /* ass2 */
  outputs: (Assignments,  /* updated ass1 */
            Assignments)  /* updated ass2 */"
  input Integer v;
  input Integer e;
  input BackendDAE.Assignments ass1;
  input BackendDAE.Assignments ass2;
  output BackendDAE.Assignments outAssignments1;
  output BackendDAE.Assignments outAssignments2;
algorithm
  outAssignments1 := assignmentsSetnth(ass1, v, e);
  outAssignments2 := assignmentsSetnth(ass2, e, v);
end assign;

protected function forallUnmarkedVarsInEqn
"function: forallUnmarkedVarsInEqn
  author: PA
  This function is part of the matching algorithm.
  It loops over all umarked variables in an equation.
  inputs:  (IncidenceMatrix,
            IncidenceMatrixT,
            int,
            BackendDAE.Assignments /* ass1 */,
            BackendDAE.Assignments /* ass2 */)
  outputs: (Assignments, Assignments)"
  input BackendDAE.IncidenceMatrix m;
  input BackendDAE.IncidenceMatrixT mt;
  input Integer i;
  input BackendDAE.Assignments ass1;
  input BackendDAE.Assignments ass2;
  output BackendDAE.Assignments outAssignments1;
  output BackendDAE.Assignments outAssignments2;
protected
  list<Integer> vars,vars_1;
algorithm
  vars := BackendDAEUtil.varsInEqn(m, i);
  vars_1 := List.filter(vars, isNotVMarked);
 (outAssignments1,outAssignments2) := forallUnmarkedVarsInEqnBody(m, mt, i, vars_1, ass1, ass2);
end forallUnmarkedVarsInEqn;

protected function isNotVMarked
"function: isNotVMarked
  author: PA
  This function succeds for variables that are not marked."
  input Integer i;
algorithm
  false := BackendDAEEXT.getVMark(i);
end isNotVMarked;

protected function forallUnmarkedVarsInEqnBody
"function: forallUnmarkedVarsInEqnBody
  author: PA
  This function is part of the matching algorithm.
  It is the body of the loop over all unmarked variables.
  inputs:  (IncidenceMatrix, BackendDAE.IncidenceMatrixT,
            int,
            int list /* var list */
            Assignments
            Assignments)
  outputs: (Assignments, Assignments)"
  input BackendDAE.IncidenceMatrix m;
  input BackendDAE.IncidenceMatrixT mt;
  input Integer i;
  input list<Integer> inIntegerLst4;
  input BackendDAE.Assignments ass1;
  input BackendDAE.Assignments ass2;
  output BackendDAE.Assignments outAssignments1;
  output BackendDAE.Assignments outAssignments2;
algorithm
  (outAssignments1,outAssignments2):=
  matchcontinue (m,mt,i,inIntegerLst4,ass1,ass2)
    local
      Integer assarg,v;
      BackendDAE.Assignments ass1_1,ass2_1,ass1_2,ass2_2;
      list<Integer> vars,vs;
    case (_,_,_,(vars as (v :: vs)),_,_)
      equation
        BackendDAEEXT.vMark(v);
        assarg = getAssigned(v, ass1);
        (ass1_1,ass2_1) = pathFound(m, mt, assarg, ass1, ass2);
        (ass1_2,ass2_2) = assign(v, i, ass1_1, ass2_1);
      then
        (ass1_2,ass2_2);
    case (_,_,_,(vars as (v :: vs)),_,_)
      equation
        BackendDAEEXT.vMark(v);
        (ass1_1,ass2_1) = forallUnmarkedVarsInEqnBody(m, mt, i, vs, ass1, ass2);
      then
        (ass1_1,ass2_1);
  end matchcontinue;
end forallUnmarkedVarsInEqnBody;

/******************************************
 strongComponents and stuff
 *****************************************/

public function strongComponentsScalar "function: strongComponents
  author: PA

  This is the second part of the BLT sorting. It takes the variable
  assignments and the incidence matrix as input and identifies strong
  components, i.e. subsystems of equations.

  inputs:  (IncidenceMatrix, BackendDAE.IncidenceMatrixT, int vector, int vector)
  outputs: (int list list /* list of components */ )
"
  input BackendDAE.EqSystem syst;
  input BackendDAE.Shared shared;
  input array<list<Integer>> mapEqnIncRow;
  input array<Integer> mapIncRowEqn;  
  output BackendDAE.EqSystem osyst;
  output BackendDAE.StrongComponents outComps;
algorithm
  (osyst,outComps) :=
  matchcontinue (syst,shared,mapEqnIncRow,mapIncRowEqn)
    local
      list<list<Integer>> comps;
      array<Integer> ass1,ass2;
      BackendDAE.IncidenceMatrix m;
      BackendDAE.IncidenceMatrixT mt;
      BackendDAE.StrongComponents comps1;
      BackendDAE.EquationArray eqs;
      BackendDAE.Variables vars;
      array<Integer> markarray;
    case (BackendDAE.EQSYSTEM(vars,eqs,SOME(m),SOME(mt),BackendDAE.MATCHING(ass1,ass2,_)),_,_,_)
      equation
        comps = tarjanAlgorithm(m,mt,ass1,ass2);
        markarray = arrayCreate(BackendDAEUtil.equationArraySize(eqs),-1);
        comps1 = analyseStrongComponentsScalar(comps,syst,shared,ass1,ass2,mapEqnIncRow,mapIncRowEqn,1,markarray,{});
        ass1 = varAssignmentNonScalar(1,arrayLength(ass1),ass1,mapIncRowEqn,{});
        //noscalass2 = eqnAssignmentNonScalar(1,arrayLength(mapEqnIncRow),mapEqnIncRow,ass2,{});
      then
        (BackendDAE.EQSYSTEM(vars,eqs,NONE(),NONE(),BackendDAE.MATCHING(ass1,ass2,comps1)),comps1);
        // Frenkel TUD: Do not hand over the scalar incidence Matrix because following modules does not check if scalar or not
        //(BackendDAE.EQSYSTEM(vars,eqs,SOME(m),SOME(mt),BackendDAE.MATCHING(ass1,ass2,comps1)),comps1);
    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR, {"sorting equations(strongComponents failed)"});
      then fail();
  end matchcontinue;
end strongComponentsScalar;

public function eqnAssignmentNonScalar
  input Integer index;
  input Integer size;
  input array<list<Integer>> mapEqnIncRow;
  input array<Integer> ass2;
  input list<list<Integer>> iAcc;
  output array<list<Integer>> oAcc;
algorithm
  oAcc := matchcontinue(index,size,mapEqnIncRow,ass2,iAcc)
    local
      list<Integer> elst,vlst;
    case (_,_,_,_,_)
      equation
        false = intGt(index,size);
        elst = mapEqnIncRow[index];
        vlst = List.map1r(elst,arrayGet,ass2);
        vlst = List.select1(vlst,intGt,0);
      then
        eqnAssignmentNonScalar(index+1,size,mapEqnIncRow,ass2,vlst::iAcc);
    else
      then
        listArray(listReverse(iAcc));
  end matchcontinue;
end eqnAssignmentNonScalar;

public function varAssignmentNonScalar
  input Integer index;
  input Integer size;
  input array<Integer> ass1;
  input array<Integer> mapIncRowEqn; 
  input list<Integer> iAcc;
  output array<Integer> oAcc;
algorithm
  oAcc := matchcontinue(index,size,ass1,mapIncRowEqn,iAcc)
    local
      Integer e;
    case (_,_,_,_,_)
      equation
        false = intGt(index,size);
        e = ass1[index];
        true = intGt(e,0);
        e = mapIncRowEqn[e];
      then
        varAssignmentNonScalar(index+1,size,ass1,mapIncRowEqn,e::iAcc);
    case (_,_,_,_,_)
      equation
        false = intGt(index,size);
        e = ass1[index];
        false = intGt(e,0);
        e = -1;
      then
        varAssignmentNonScalar(index+1,size,ass1,mapIncRowEqn,e::iAcc);
    else
      then
        listArray(listReverse(iAcc));
  end matchcontinue;
end varAssignmentNonScalar;

protected function analyseStrongComponentsScalar"function: analyseStrongComponents
  author: Frenkel TUD 2011-05
  analyse the type of the strong connect components and
  calculate the jacobian."
  input list<list<Integer>> inComps;
  input BackendDAE.EqSystem syst;
  input BackendDAE.Shared shared; 
  input array<Integer> inAss1;
  input array<Integer> inAss2;  
  input array<list<Integer>> mapEqnIncRow;
  input array<Integer> mapIncRowEqn;
  input Integer imark;
  input array<Integer> markarray;
  input BackendDAE.StrongComponents iAcc;
  output BackendDAE.StrongComponents outComps;
algorithm
  outComps:=
  match (inComps,syst,shared,inAss1,inAss2,mapEqnIncRow,mapIncRowEqn,imark,markarray,iAcc)
    local
      list<Integer> comp;
      list<list<Integer>> comps;
      BackendDAE.StrongComponent acomp;
      Integer mark;
    case ({},_,_,_,_,_,_,_,_,_) then listReverse(iAcc);
    case (comp::comps,_,_,_,_,_,_,_,_,_)
      equation
        (acomp,mark) = analyseStrongComponentScalar(comp,syst,shared,inAss1,inAss2,mapEqnIncRow,mapIncRowEqn,imark,markarray);
      then
        analyseStrongComponentsScalar(comps,syst,shared,inAss1,inAss2,mapEqnIncRow,mapIncRowEqn,mark,markarray,acomp::iAcc);
    else
      equation
        print("- BackendDAETransform.analyseStrongComponents failed\n");
      then
        fail();        
  end match;  
end analyseStrongComponentsScalar;

protected function analyseStrongComponentScalar"function: analyseStrongComponent
  author: Frenkel TUD 2011-05 
  helper for analyseStrongComponents."
  input list<Integer> inComp;
  input BackendDAE.EqSystem syst;
  input BackendDAE.Shared shared;  
  input array<Integer> inAss1;
  input array<Integer> inAss2;  
  input array<list<Integer>> mapEqnIncRow;
  input array<Integer> mapIncRowEqn;   
  input Integer imark;
  input array<Integer> markarray;  
  output BackendDAE.StrongComponent outComp;
  output Integer omark;
algorithm
  (outComp,omark):=
  match (inComp,syst,shared,inAss1,inAss2,mapEqnIncRow,mapIncRowEqn,imark,markarray)
    local
      list<Integer> comp,vlst,eqngetlst;
      list<BackendDAE.Var> varlst;
      list<tuple<BackendDAE.Var,Integer>> var_varindx_lst;
      array<Integer> ass1,ass2;
      BackendDAE.Variables vars;
      list<BackendDAE.Equation> eqn_lst;
      BackendDAE.EquationArray eqns;
      BackendDAE.StrongComponent compX;
      Integer mark,low,high;
      Boolean foundequal;
    case (comp,syst as BackendDAE.EQSYSTEM(orderedVars=vars,orderedEqs=eqns),shared,ass1,ass2,_,_,_,_)
      equation
        vlst = List.map1r(comp,arrayGet,ass2);
        varlst = List.map1r(vlst,BackendVariable.getVarAt,vars);
        var_varindx_lst = List.threadTuple(varlst,vlst);
        // get from scalar eqns indexes the indexes in the equation array
        comp = List.map1r(comp,arrayGet,mapIncRowEqn);
        comp = List.fold2(comp,uniqueComp,imark,markarray,{});
        //comp = List.unique(comp);
        eqngetlst = List.map1(comp,intSub,1);
        eqn_lst = List.map1r(eqngetlst,BackendDAEUtil.equationNth,eqns);
        compX = analyseStrongComponentBlock(comp,eqn_lst,var_varindx_lst,syst,shared,ass1,ass2,false);   
      then
        (compX,imark+1);
    else
      equation
        print("- BackendDAETransform.analyseStrongComponent failed\n");
      then
        fail();          
  end match;  
end analyseStrongComponentScalar;


protected function uniqueComp
  input Integer c;
  input Integer mark;
  input array<Integer> markarray;
  input list<Integer> iAcc;
  output list<Integer> oAcc;
algorithm
  oAcc := matchcontinue(c,mark,markarray,iAcc)
    case(_,_,_,_)
      equation
        false = intEq(mark,markarray[c]);
        _ = arrayUpdate(markarray,c,mark);
      then
        c::iAcc;
    else
      then
        iAcc;
  end matchcontinue;
end uniqueComp;


public function strongComponents "function: strongComponents
  author: PA

  This is the second part of the BLT sorting. It takes the variable
  assignments and the incidence matrix as input and identifies strong
  components, i.e. subsystems of equations.

  inputs:  (IncidenceMatrix, BackendDAE.IncidenceMatrixT, int vector, int vector)
  outputs: (int list list /* list of components */ )
"
  input BackendDAE.EqSystem syst;
  input BackendDAE.Shared shared;
  output BackendDAE.EqSystem osyst;
  output BackendDAE.StrongComponents outComps;
algorithm
  (osyst,outComps) :=
  matchcontinue (syst,shared)
    local
      list<list<Integer>> comps;
      array<Integer> ass1,ass2;
      BackendDAE.IncidenceMatrix m;
      BackendDAE.IncidenceMatrixT mt;
      BackendDAE.StrongComponents comps1;
      BackendDAE.EquationArray eqs;
      BackendDAE.Variables vars;
    case (BackendDAE.EQSYSTEM(vars,eqs,SOME(m),SOME(mt),BackendDAE.MATCHING(ass1,ass2,_)),_)
      equation
        comps = tarjanAlgorithm(m,mt,ass1,ass2);
        comps1 = analyseStrongComponents(comps,syst,shared,ass1,ass2,{});
      then
        (BackendDAE.EQSYSTEM(vars,eqs,SOME(m),SOME(mt),BackendDAE.MATCHING(ass1,ass2,comps1)),comps1);
    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR, {"sorting equations(strongComponents failed)"});
      then fail();
  end matchcontinue;
end strongComponents;

protected function analyseStrongComponents"function: analyseStrongComponents
  author: Frenkel TUD 2011-05
  analyse the type of the strong connect components and
  calculate the jacobian."
  input list<list<Integer>> inComps;
  input BackendDAE.EqSystem syst;
  input BackendDAE.Shared shared; 
  input array<Integer> inAss1;
  input array<Integer> inAss2;  
  input BackendDAE.StrongComponents iAcc;
  output BackendDAE.StrongComponents outComps;
algorithm
  outComps:=
  match (inComps,syst,shared,inAss1,inAss2,iAcc)
    local
      list<Integer> comp;
      list<list<Integer>> comps;
      BackendDAE.StrongComponent acomp;
    case ({},_,_,_,_,_) then listReverse(iAcc);
    case (comp::comps,_,_,_,_,_)
      equation
        acomp = analyseStrongComponent(comp,syst,shared,inAss1,inAss2);
      then
        analyseStrongComponents(comps,syst,shared,inAss1,inAss2,acomp::iAcc);
    else
      equation
        print("- BackendDAETransform.analyseStrongComponents failed\n");
      then
        fail();        
  end match;  
end analyseStrongComponents;

protected function analyseStrongComponent"function: analyseStrongComponent
  author: Frenkel TUD 2011-05 
  helper for analyseStrongComponents."
  input list<Integer> inComp;
  input BackendDAE.EqSystem syst;
  input BackendDAE.Shared shared;  
  input array<Integer> inAss1;
  input array<Integer> inAss2;  
  output BackendDAE.StrongComponent outComp;
algorithm
  outComp:=
  match (inComp,syst,shared,inAss1,inAss2)
    local
      list<Integer> comp;
      list<tuple<BackendDAE.Var,Integer>> var_varindx_lst;
      array<Integer> ass1,ass2;
      BackendDAE.Variables vars;
      list<BackendDAE.Equation> eqn_lst;
      BackendDAE.EquationArray eqns;
      BackendDAE.StrongComponent compX;
    case (comp,syst as BackendDAE.EQSYSTEM(orderedVars=vars,orderedEqs=eqns),shared,ass1,ass2)
      equation
        (eqn_lst,var_varindx_lst) = List.map3_2(comp, getEquationAndSolvedVar_Internal, eqns, vars, ass2);
        compX = analyseStrongComponentBlock(comp,eqn_lst,var_varindx_lst,syst,shared,ass1,ass2,false);   
      then
        compX;
    else
      equation
        print("- BackendDAETransform.analyseStrongComponent failed\n");
      then
        fail();          
  end match;  
end analyseStrongComponent;

protected function analyseStrongComponentBlock"function: analyseStrongComponentBlock
  author: Frenkel TUD 2011-05 
  helper for analyseStrongComponent."
  input list<Integer> inComp;  
  input list<BackendDAE.Equation> inEqnLst;
  input list<tuple<BackendDAE.Var,Integer>> inVarVarindxLst; 
  input BackendDAE.EqSystem isyst;
  input BackendDAE.Shared ishared;  
  input array<Integer> inAss1;
  input array<Integer> inAss2;
  input Boolean inLoop; //true if the function call itself
  output BackendDAE.StrongComponent outComp;
algorithm
  outComp:=
  matchcontinue (inComp,inEqnLst,inVarVarindxLst,isyst,ishared,inAss1,inAss2,inLoop)
    local
      Integer compelem,v;
      list<Integer> comp,varindxs;
      list<tuple<BackendDAE.Var,Integer>> var_varindx_lst,var_varindx_lst_cond;
      array<Integer> ass1,ass2;
      BackendDAE.IncidenceMatrix m;
      BackendDAE.IncidenceMatrixT mt;
      BackendDAE.Variables vars,evars,vars_1;
      list<BackendDAE.Equation> eqn_lst,cont_eqn,disc_eqn;
      list<BackendDAE.Var> var_lst,var_lst_1,cont_var,disc_var;
      list<Integer> indxcont_var,indxdisc_var,indxcont_eqn,indxdisc_eqn;
      BackendDAE.Variables av;
      BackendDAE.EquationArray eqns_1,eqns,eeqns;
      array<DAE.Constraint> constrs;
      array<DAE.ClassAttributes> clsAttrs;
      Env.Cache cache;
      Env.Env env;      
      DAE.FunctionTree funcs;
      Option<list<tuple<Integer, Integer, BackendDAE.Equation>>> jac;
      BackendDAE.JacobianType jac_tp;
      BackendDAE.StrongComponent sc;
      BackendDAE.EqSystem syst;
      BackendDAE.Shared shared;
      String msg;
      list<DAE.ComponentRef> crlst;
      list<String> slst;

    case (compelem::{},BackendDAE.ALGORITHM(size = _)::{},var_varindx_lst,_,_,_,_,false)
      equation
        varindxs = List.map(var_varindx_lst,Util.tuple22);        
      then
        BackendDAE.SINGLEALGORITHM(compelem,varindxs);
    case (compelem::{},BackendDAE.ARRAY_EQUATION(dimSize = _)::{},var_varindx_lst,_,_,_,_,false)
      equation
        varindxs = List.map(var_varindx_lst,Util.tuple22);        
      then
        BackendDAE.SINGLEARRAY(compelem,varindxs);
    case (compelem::{},BackendDAE.COMPLEX_EQUATION(size=_)::{},var_varindx_lst,_,_,_,_,false)
      equation
        varindxs = List.map(var_varindx_lst,Util.tuple22);        
      then
        BackendDAE.SINGLECOMPLEXEQUATION(compelem,varindxs);        
    case (compelem::{},_,(_,v)::{},_,_,_,ass2,false)
      then BackendDAE.SINGLEEQUATION(compelem,v);        
    case (comp,eqn_lst,var_varindx_lst,syst as BackendDAE.EQSYSTEM(orderedVars=vars,orderedEqs=eqns),shared,ass1,ass2,false)
      equation
        var_lst = List.map(var_varindx_lst,Util.tuple21);
        true = BackendVariable.hasDiscreteVar(var_lst);
        true = BackendVariable.hasContinousVar(var_lst);
        varindxs = List.map(var_varindx_lst,Util.tuple22);
        (cont_eqn,cont_var,disc_eqn,disc_var,indxcont_eqn,indxcont_var,indxdisc_eqn,indxdisc_var) = splitMixedEquations(eqn_lst, comp, var_lst, varindxs);
        var_varindx_lst_cond = List.threadTuple(cont_var,indxcont_var);
        sc = analyseStrongComponentBlock(indxcont_eqn,cont_eqn,var_varindx_lst_cond,syst,shared,ass1,ass2,true);
      then
        BackendDAE.MIXEDEQUATIONSYSTEM(sc,indxdisc_eqn,indxdisc_var);    
    case (comp,eqn_lst,var_varindx_lst,syst as BackendDAE.EQSYSTEM(orderedVars=vars,orderedEqs=eqns),shared as BackendDAE.SHARED(constraints=constrs,classAttrs=clsAttrs,cache=cache,env=env,functionTree=funcs),ass1,ass2,_)
      equation
        var_lst = List.map(var_varindx_lst,Util.tuple21);
        false = BackendVariable.hasDiscreteVar(var_lst);
        varindxs = List.map(var_varindx_lst,Util.tuple22);
        eqn_lst = replaceDerOpInEquationList(eqn_lst);
        // States are solved for der(x) not x.
        var_lst_1 = List.map(var_lst, transformXToXd);
        vars_1 = BackendDAEUtil.listVar1(var_lst_1);
        eqns_1 = BackendDAEUtil.listEquation(eqn_lst);
        av = BackendDAEUtil.emptyVars();
        eeqns = BackendDAEUtil.listEquation({});
        evars = BackendDAEUtil.listVar1({});
        syst = BackendDAE.EQSYSTEM(vars_1,eqns_1,NONE(),NONE(),BackendDAE.NO_MATCHING());
        shared = BackendDAE.SHARED(evars,evars,av,eeqns,eeqns,constrs,clsAttrs,cache,env,funcs,BackendDAE.EVENT_INFO({},{}),{},BackendDAE.ALGEQSYSTEM(),{});
        (m,mt) = BackendDAEUtil.incidenceMatrix(syst,BackendDAE.ABSOLUTE());
        // calculate jacobian. If constant, linear system of equations. Otherwise nonlinear
        jac = BackendDAEUtil.calculateJacobian(vars_1, eqns_1, m, true,shared);
        // Jacobian of a Linear System is always linear 
        jac_tp = BackendDAEUtil.analyzeJacobian(vars_1,eqns_1,jac);
      then
        BackendDAE.EQUATIONSYSTEM(comp,varindxs,jac,jac_tp);
    case (comp,eqn_lst,var_varindx_lst,syst as BackendDAE.EQSYSTEM(orderedVars=vars,orderedEqs=eqns),shared,ass1,ass2,_)
      equation
        var_lst = List.map(var_varindx_lst,Util.tuple21);
        true = BackendVariable.hasDiscreteVar(var_lst);
        false = BackendVariable.hasContinousVar(var_lst);
        msg = "Sorry - Support for Discrete Equation Systems is not yed implemented\n";
        crlst = List.map(var_lst,BackendVariable.varCref);
        slst = List.map(crlst,ComponentReference.printComponentRefStr);
        msg = msg +& stringDelimitList(slst,"\n");
        slst = List.map(eqn_lst,BackendDump.equationStr);
        msg = msg +& "\n" +& stringDelimitList(slst,"\n");
        Error.addMessage(Error.INTERNAL_ERROR, {msg});
      then
        fail();            
    else
      equation
        msg = "BackendDAETransform.analyseStrongComponentBlock failed";
        Error.addMessage(Error.INTERNAL_ERROR, {msg});
      then
        fail();          
  end matchcontinue;  
end analyseStrongComponentBlock;

protected function transformXToXd "function transformXToXd
  author: PA
  this function transforms x variables (in the state vector)
  to corresponding xd variable (in the derivatives vector)"
  input BackendDAE.Var inVar;
  output BackendDAE.Var outVar;
algorithm
  outVar := matchcontinue (inVar)
    local
      Expression.ComponentRef cr;
      DAE.VarDirection dir;
      DAE.VarParallelism prl;
      BackendDAE.Type tp;
      Option<DAE.Exp> exp;
      Option<Values.Value> v;
      list<Expression.Subscript> dim;
      Option<DAE.VariableAttributes> attr;
      Option<SCode.Comment> comment;
      DAE.ConnectorType ct;
      DAE.ElementSource source "the origin of the element";
      BackendDAE.Var backendVar;
      
    case (BackendDAE.VAR(varName = cr,
      varKind = BackendDAE.STATE(),
      varDirection = dir,
      varParallelism = prl,
      varType = tp,
      bindExp = exp,
      bindValue = v,
      arryDim = dim,
      source = source,
      values = attr,
      comment = comment,
      connectorType = ct))
      equation
        cr = ComponentReference.crefPrefixDer(cr);
      then
        BackendDAE.VAR(cr,BackendDAE.STATE_DER(),dir,prl,tp,exp,v,dim,source,attr,comment,ct);
        
    case (backendVar)
    then
      backendVar;
  end matchcontinue;
end transformXToXd;

protected function replaceDerOpInEquationList
  "Replaces all der(cref) with $DER.cref in a list of equations."
  input list<BackendDAE.Equation> inEqns;
  output list<BackendDAE.Equation> outEqns;
algorithm
  (outEqns,_) := BackendEquation.traverseBackendDAEExpsEqnList(inEqns, replaceDerOpInExp,0);
end replaceDerOpInEquationList;

protected function replaceDerOpInExp
  "Replaces all der(cref) with $DER.cref in an expression."
    input tuple<DAE.Exp, Integer> inTpl;
    output tuple<DAE.Exp, Integer> outTpl;
protected
  DAE.Exp exp,exp1;
  Integer i;
algorithm
  (exp,i) := inTpl;
  ((exp1, _)) := Expression.traverseExp(exp, replaceDerOpInExpTraverser, NONE());
  outTpl := ((exp1,i));
end replaceDerOpInExp;

protected function replaceDerOpInExpTraverser
  "Used with Expression.traverseExp to traverse an expression an replace calls to
  der(cref) with a component reference $DER.cref. If an optional component
  reference is supplied, then only that component reference is replaced.
  Otherwise all calls to der are replaced.
  
  This is done since some parts of the compiler can't handle der-calls, such as
  Derive.differentiateExpression. Ideally these parts should be fixed so that they can
  handle der-calls, but until that happens we just replace the der-calls with
  crefs."
  input tuple<DAE.Exp, Option<DAE.ComponentRef>> inExp;
  output tuple<DAE.Exp, Option<DAE.ComponentRef>> outExp;
algorithm
  outExp := matchcontinue(inExp)
    local
      DAE.ComponentRef cr, der_cr;
      DAE.Exp cref_exp;
      DAE.ComponentRef cref;
      
    case ((DAE.CALL(path = Absyn.IDENT("der"),expLst = {DAE.CREF(componentRef = cr)}),
        SOME(cref)))
      equation
        der_cr = ComponentReference.crefPrefixDer(cr);
        true = ComponentReference.crefEqualNoStringCompare(der_cr, cref);
        cref_exp = Expression.crefExp(der_cr);
      then
        ((cref_exp, SOME(cref)));
        
    case ((DAE.CALL(path = Absyn.IDENT("der"),expLst = {DAE.CREF(componentRef = cr)}),
        NONE()))
      equation
        cr = ComponentReference.crefPrefixDer(cr);
        cref_exp = Expression.crefExp(cr);
      then
        ((cref_exp, NONE()));
    case (_) then inExp;
  end matchcontinue;
end replaceDerOpInExpTraverser;

public function getEquationAndSolvedVar
"function: getEquationAndSolvedVar
  author: PA
  Retrieves the equation and the variable solved in that equation
  given an equation number and the variable assignments2"
  input BackendDAE.StrongComponent inComp;
  input BackendDAE.EquationArray inEquationArray;
  input BackendDAE.Variables inVariables;
  output list<BackendDAE.Equation> outEquation;
  output list<BackendDAE.Var> outVar;
  output Integer outIndex;
algorithm
  (outEquation,outVar,outIndex):=
  matchcontinue (inComp,inEquationArray,inVariables)
    local
      Integer e_1,v,e;
      list<Integer> elst,vlst;
      BackendDAE.Equation eqn;
      BackendDAE.Var var;
      list<BackendDAE.Equation> eqnlst,eqnlst1;
      list<BackendDAE.Var> varlst,varlst1;
      BackendDAE.EquationArray eqns;
      BackendDAE.Variables vars;
      BackendDAE.StrongComponent comp;
      list<tuple<Integer,list<Integer>>> eqnvartpllst;
    case (BackendDAE.SINGLEEQUATION(eqn=e,var=v),eqns,vars) 
      equation
        e_1 = e - 1;
        eqn = BackendDAEUtil.equationNth(eqns, e_1);
        var = BackendVariable.getVarAt(vars, v);
      then
        ({eqn},{var},e);
    case (BackendDAE.MIXEDEQUATIONSYSTEM(condSystem=comp,disc_eqns=elst,disc_vars=vlst),eqns,vars) 
      equation
        eqnlst1 = BackendEquation.getEqns(elst,eqns);   
        varlst1 = List.map1r(vlst, BackendVariable.getVarAt, vars);
        e = List.first(elst);        
        (eqnlst,varlst,_) = getEquationAndSolvedVar(comp,eqns,vars);
        eqnlst = listAppend(eqnlst,eqnlst1);
        varlst = listAppend(varlst,varlst1);
      then
        (eqnlst,varlst,e);          
    case (BackendDAE.EQUATIONSYSTEM(eqns=elst,vars=vlst),eqns,vars) 
      equation
        eqnlst = BackendEquation.getEqns(elst,eqns);        
        varlst = List.map1r(vlst, BackendVariable.getVarAt, vars);
        e = List.first(elst);        
      then
        (eqnlst,varlst,e);        
    case (BackendDAE.SINGLEARRAY(eqn=e,vars=vlst),eqns,vars) 
      equation
        e_1 = e - 1;
        eqn = BackendDAEUtil.equationNth(eqns, e_1);
        varlst = List.map1r(vlst, BackendVariable.getVarAt, vars);
      then
        ({eqn},varlst,e);  
    case (BackendDAE.SINGLEALGORITHM(eqn=e,vars=vlst),eqns,vars)
      equation
        e_1 = e - 1;
        eqn = BackendDAEUtil.equationNth(eqns, e_1);
        varlst = List.map1r(vlst, BackendVariable.getVarAt, vars);
      then
        ({eqn},varlst,e);
    case (BackendDAE.SINGLECOMPLEXEQUATION(eqn=e,vars=vlst),eqns,vars)
      equation
        e_1 = e - 1;
        eqn = BackendDAEUtil.equationNth(eqns, e_1);
        varlst = List.map1r(vlst, BackendVariable.getVarAt, vars);
      then
        ({eqn},varlst,e);
    case (BackendDAE.TORNSYSTEM(tearingvars=vlst, residualequations=elst, otherEqnVarTpl=eqnvartpllst),eqns,vars) 
      equation
        eqnlst = BackendEquation.getEqns(elst,eqns);        
        varlst = List.map1r(vlst, BackendVariable.getVarAt, vars);
        eqnlst1 = BackendEquation.getEqns(List.map(eqnvartpllst,Util.tuple21),eqns);        
        varlst1 = List.map1r(List.flatten(List.map(eqnvartpllst,Util.tuple22)), BackendVariable.getVarAt, vars);
        eqnlst = listAppend(eqnlst,eqnlst1);
        varlst = listAppend(varlst,varlst1);        
        e = List.first(elst);        
      then
        (eqnlst,varlst,e);        
    case (inComp,eqns,vars)
      equation
        true = Flags.isSet(Flags.FAILTRACE);
        Debug.traceln("BackendDAETransform.getEquationAndSolvedVar failed!");
      then
        fail();
  end matchcontinue;
end getEquationAndSolvedVar;

protected function getEquationAndSolvedVar_Internal
"function: getEquationAndSolvedVar_Internal
  author: PA
  Retrieves the equation and the variable solved in that equation
  given an equation number and the variable assignments2"
  input Integer inInteger;
  input BackendDAE.EquationArray inEquationArray;
  input BackendDAE.Variables inVariables;
  input array<Integer> inIntegerArray;
  output BackendDAE.Equation outEquation;
  output tuple<BackendDAE.Var,Integer> outVar;
algorithm
  (outEquation,outVar):=
  matchcontinue (inInteger,inEquationArray,inVariables,inIntegerArray)
    local
      Integer e_1,v,e;
      BackendDAE.Equation eqn;
      BackendDAE.Var var;
      BackendDAE.EquationArray eqns;
      BackendDAE.Variables vars;
      array<Integer> ass2;
    case (e,eqns,vars,ass2) /* equation no. assignments2 */
      equation
        e_1 = e - 1;
        eqn = BackendDAEUtil.equationNth(eqns, e_1);
        v = ass2[e];
        var = BackendVariable.getVarAt(vars, v);
      then
        (eqn,(var,v));
    case (e,eqns,vars,ass2) /* equation no. assignments2 */
      equation
        true = Flags.isSet(Flags.FAILTRACE);
        Debug.traceln("BackendDAETransform.getEquationAndSolvedVar_Internal failed at index: " +& intString(e));
      then
        fail();
  end matchcontinue;
end getEquationAndSolvedVar_Internal;

public function getEquationAndSolvedVarIndxes
"function: getEquationAndSolvedVarIndxes
  author: Frenkel TUD
  Retrieves the equation and the variable indexes solved in that equation
  given an equation number and the variable assignments2"
  input BackendDAE.StrongComponent inComp;
  output list<Integer> outEquation;
  output list<Integer> outVar;
algorithm
  (outEquation,outVar):=
  matchcontinue(inComp)
    local
      Integer v,e;
      list<Integer> elst,vlst,elst1,vlst1;
      BackendDAE.StrongComponent comp;
      list<tuple<Integer,list<Integer>>> eqnvartpllst;
    case (BackendDAE.SINGLEEQUATION(eqn=e,var=v)) 
      then
        ({e},{v});
    case BackendDAE.MIXEDEQUATIONSYSTEM(condSystem=comp,disc_eqns=elst,disc_vars=vlst)
      equation       
        (elst1,vlst1) = getEquationAndSolvedVarIndxes(comp);
        elst = listAppend(elst1,elst);
        vlst = listAppend(vlst1,vlst);
      then
        (elst,vlst);
    case BackendDAE.EQUATIONSYSTEM(eqns=elst,vars=vlst)   
      then
        (elst,vlst);
    case BackendDAE.SINGLEARRAY(eqn=e,vars=vlst)
      then
        ({e},vlst);
    case BackendDAE.SINGLEALGORITHM(eqn=e,vars=vlst)
      then
        ({e},vlst);
    case BackendDAE.SINGLECOMPLEXEQUATION(eqn=e,vars=vlst)
      then
        ({e},vlst);
    case BackendDAE.TORNSYSTEM(tearingvars=vlst, residualequations=elst, otherEqnVarTpl=eqnvartpllst)
      equation       
        elst1 = List.map(eqnvartpllst,Util.tuple21);
        vlst1 = List.flatten(List.map(eqnvartpllst,Util.tuple22));
        elst = listAppend(elst1,elst);
        vlst = listAppend(vlst1,vlst);
      then
        (elst,vlst);         
    else
      equation
        true = Flags.isSet(Flags.FAILTRACE);
        Debug.traceln("BackendDAETransform.getEquationAndSolvedVarIndxes failed!");
      then
        fail();
  end matchcontinue;
end getEquationAndSolvedVarIndxes;

public function splitMixedEquations "function: splitMixedEquations
  author: PA

  Splits the equation of a mixed equation system into its continuous and
  discrete parts.

  Even though the matching algorithm might say that a discrete variable is solved in a specific equation
  (when part of a mixed system) this is not always correct. It might be impossible to solve the discrete
  variable from that equation, for instance solving v from equation x = v < 0; This happens for e.g. the Gear model.
  Instead, to split the equations and variables the following scheme is used:

  1. Split the variables into continuous and discrete.
  2. For each discrete variable v, select among the equations where it is present
   for an equation v = expr. (This could be done
   by looking at incidence matrix but for now we look through all equations. This is sufficiently
   efficient for small systems of mixed equations < 100)
  3. The equations not selected in step 2 are continuous equations.
"
  input list<BackendDAE.Equation> eqnLst;
  input list<Integer> indxEqnLst;
  input list<BackendDAE.Var> varLst;
  input list<Integer> indxVarLst;
  output list<BackendDAE.Equation> contEqnLst;
  output list<BackendDAE.Var> contVarLst;
  output list<BackendDAE.Equation> discEqnLst;
  output list<BackendDAE.Var> discVarLst;
  output list<Integer> indxcontEqnLst;
  output list<Integer> indxcontVarLst;
  output list<Integer> indxdiscEqnLst;
  output list<Integer> indxdiscVarLst;
algorithm
  (contEqnLst,contVarLst,discEqnLst,discVarLst,indxcontEqnLst,indxcontVarLst,indxdiscEqnLst,indxdiscVarLst):=
  match (eqnLst, indxEqnLst, varLst, indxVarLst)
    local list<tuple<BackendDAE.Equation,Integer>> eqnindxlst;
    case (eqnLst,indxEqnLst,varLst,indxVarLst) equation
      (discVarLst,contVarLst,indxdiscVarLst,indxcontVarLst) = splitVars(varLst,indxVarLst,BackendDAEUtil.isVarDiscrete,{},{},{},{});
      eqnindxlst = List.map1(discVarLst,findDiscreteEquation,(eqnLst,indxEqnLst));
      discEqnLst = List.map(eqnindxlst,Util.tuple21);
      indxdiscEqnLst = List.map(eqnindxlst,Util.tuple22);
      contEqnLst = List.setDifferenceOnTrue(eqnLst,discEqnLst,BackendEquation.equationEqual);
      indxcontEqnLst = List.setDifferenceOnTrue(indxEqnLst,indxdiscEqnLst,intEq);
    then (contEqnLst,contVarLst,discEqnLst,discVarLst,indxcontEqnLst,indxcontVarLst,indxdiscEqnLst,indxdiscVarLst);
  end match;
end splitMixedEquations;

public function splitVars
  "Helper function to splitMixedEquations."
  input list<Type_a> inList;
  input list<Type_b> inListb;
  input PredicateFunc inFunc;
  input list<Type_a> inTrueList;
  input list<Type_a> inFalseList;
  input list<Type_b> inTrueListb;
  input list<Type_b> inFalseListb;
  output list<Type_a> outTrueList;
  output list<Type_a> outFalseList;
  output list<Type_b> outTrueListb;
  output list<Type_b> outFalseListb;

  replaceable type Type_a subtypeof Any;
  replaceable type Type_b subtypeof Any;

  partial function PredicateFunc
    input Type_a inElement;
    output Boolean outResult;
  end PredicateFunc;
algorithm
  (outTrueList, outFalseList,outTrueListb, outFalseListb) := 
  match(inList, inListb, inFunc, inTrueList, inFalseList, inTrueListb, inFalseListb)
    local
      Type_a e;
      Type_b eb;
      list<Type_a> rest_e, tl, fl;
      list<Type_b> rest_eb, tlb, flb;
      Boolean pred;

    case ({}, {}, _, tl, fl, tlb, flb) 
      then (listReverse(tl), listReverse(fl),listReverse(tlb), listReverse(flb));

    case (e :: rest_e,eb :: rest_eb, _, tl, fl, tlb, flb)
      equation
        pred = inFunc(e);
        (tl, fl,tlb, flb) = splitVars1(e, rest_e,eb, rest_eb, pred, inFunc, tl, fl, tlb, flb);
      then
        (tl, fl,tlb, flb);
  end match;
end splitVars;

public function splitVars1
  "Helper function to splitVars."
  input Type_a inHead;
  input list<Type_a> inRest;
  input Type_b inHeadb;
  input list<Type_b> inRestb;
  input Boolean inPred;
  input PredicateFunc inFunc;
  input list<Type_a> inTrueList;
  input list<Type_a> inFalseList;
  input list<Type_b> inTrueListb;
  input list<Type_b> inFalseListb;
  output list<Type_a> outTrueList;
  output list<Type_a> outFalseList;
  output list<Type_b> outTrueListb;
  output list<Type_b> outFalseListb;

  replaceable type Type_a subtypeof Any;
  replaceable type Type_b subtypeof Any;

  partial function PredicateFunc
    input Type_a inElement;
    output Boolean outResult;
  end PredicateFunc;
algorithm
  (outTrueList, outFalseList,outTrueListb, outFalseListb) := 
  match(inHead, inRest,inHeadb, inRestb, inPred, inFunc, inTrueList, inFalseList,inTrueListb, inFalseListb)
    local
      list<Type_a>  tl, fl;
      list<Type_b>  tlb, flb;

    case (_, _, _, _, true, _, tl, fl, tlb, flb)
      equation
        tl = inHead :: tl;
        tlb = inHeadb :: tlb;
        (tl, fl, tlb, flb) = splitVars(inRest, inRestb, inFunc, tl, fl, tlb, flb);
      then
        (tl, fl, tlb, flb);

    case (_, _, _, _, false, _, tl, fl, tlb, flb)
      equation
        fl = inHead :: fl;
        flb = inHeadb :: flb;
        (tl, fl, tlb, flb) = splitVars(inRest, inRestb, inFunc, tl, fl, tlb, flb);
      then
        (tl, fl, tlb, flb);
  end match;
end splitVars1;

protected function findDiscreteEquation "help function to splitMixedEquations, finds the discrete equation
on the form v = expr for solving variable v"
  input BackendDAE.Var v;
  input tuple<list<BackendDAE.Equation>,list<Integer>> eqnIndxLst;
  output tuple<BackendDAE.Equation,Integer> eqnindx;
algorithm
  eqnindx := matchcontinue(v,eqnIndxLst)
    local Expression.ComponentRef cr1,cr;
      DAE.Exp e2;
      Integer i;
      BackendDAE.Equation eqn;
      list<Integer> ilst;
      list<BackendDAE.Equation> eqnLst;
      String errstr;
    case (v,(((eqn as BackendDAE.EQUATION(DAE.CREF(cr,_),e2,_))::_),i::_)) equation
      cr1=BackendVariable.varCref(v);
      true = ComponentReference.crefEqualNoStringCompare(cr1,cr);
    then ((eqn,i));
    case(v,(((eqn as BackendDAE.EQUATION(e2,DAE.CREF(cr,_),_))::_),i::_)) equation
      cr1=BackendVariable.varCref(v);
      true = ComponentReference.crefEqualNoStringCompare(cr1,cr);
    then ((eqn,i));
    case(v,(_::eqnLst,_::ilst)) equation
      ((eqn,i)) = findDiscreteEquation(v,(eqnLst,ilst));
    then ((eqn,i));
    else equation
      Error.addMessage(Error.INTERNAL_ERROR,{"BackendDAETransform.findDiscreteEquation failed.\n
Your model contains a mixed system involving algorithms or other complex-equations.\n
Sorry. Currently are supported only mixed system involving simple equations and boolean variables.\n
Try to break the loop by using the pre operator."});
      true = Flags.isSet(Flags.FAILTRACE);
      Debug.trace("findDiscreteEquation failed, searching for variables:  ");
      errstr = ComponentReference.printComponentRefStr(BackendVariable.varCref(v));
      Debug.traceln(errstr);
    then
      fail();
  end matchcontinue;
end findDiscreteEquation;

public function tarjanAlgorithm "function: tarjanAlgorithm
  author: PA

  This is the second part of the BLT sorting. It takes the variable
  assignments and the incidence matrix as input and identifies strong
  components, i.e. subsystems of equations.

  inputs:  (IncidenceMatrix, BackendDAE.IncidenceMatrixT, int vector, int vector)
  outputs: (int list list /* list of components */ )
"
  input BackendDAE.IncidenceMatrix m;
  input BackendDAE.IncidenceMatrixT mt;
  input array<Integer> ass1 "ass[varindx]=eqnindx";
  input array<Integer> ass2 "ass[eqnindx]=varindx";
  output list<list<Integer>> outComps;
algorithm
  outComps :=
  matchcontinue (m,mt,ass1,ass2)
    local
      Integer n;
      list<list<Integer>> comps;
      array<Integer> number,lowlink;
    case (_,_,_,_)
      equation
        n = arrayLength(m);
        number = arrayCreate(n,0);
        lowlink = arrayCreate(n,0);
        (_,_,comps) = strongConnectMain(m, mt, ass1, ass2, number, lowlink, n, 0, 1, {}, {});
      then
        comps;
    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR, {"-BackendDAETransform-tarjansAlgorithm failed! The sorting of the equations could not be done.(strongComponents failed), Use +d=failtrace for more information."});
      then fail();
  end matchcontinue;
end tarjanAlgorithm;

public function strongConnectMain "function: strongConnectMain
  author: PA

  Helper function to strong_components

  inputs:  (IncidenceMatrix,
              IncidenceMatrixT,
              int vector, /* Assignment */
              int vector, /* Assignment */
              int vector, /* Number */
              int vector, /* Lowlink */
              int, /* n - number of equations */
              int, /* i */
              int, /* w */
              int list, /* stack */
              int list list /* components */)
  outputs: (int /* i */, int list /* stack */, int list list /* components */)
"
  input BackendDAE.IncidenceMatrix m;
  input BackendDAE.IncidenceMatrixT mt;
  input array<Integer> a1;
  input array<Integer> a2;
  input array<Integer> number;
  input array<Integer> lowlink;
  input Integer n;
  input Integer i;
  input Integer w;
  input list<Integer> istack;
  input list<list<Integer>> icomps;
  output Integer oi;
  output list<Integer> ostack;
  output list<list<Integer>> ocomps;
algorithm
  (oi,ostack,ocomps):=
  matchcontinue (m,mt,a1,a2,number,lowlink,n,i,w,istack,icomps)
    local
      Integer i1,num;
      list<Integer> stack;
      list<list<Integer>> comps;
      
    case (_,_,_,_,_,_,_,_,_,_,_)
      equation
        (w > n) = true;
      then
        (i,istack,icomps);
    case (_,_,_,_,_,_,_,_,_,_,_)
      equation
        true = intEq(number[w],0);
        (i1,stack,comps) = strongConnect(m,mt,a1,a2,number,lowlink,i,w,istack,icomps);
        (i1,stack,comps) = strongConnectMain(m,mt,a1,a2,number,lowlink,n,i,w + 1,stack,comps);
      then
        (i1,stack,comps);
    case (_,_,_,_,_,_,_,_,_,_,_)
      equation
        num = number[w];
        (num == 0) = false;
        (i1,stack,comps) = strongConnectMain(m,mt,a1,a2,number,lowlink, n, i, w + 1, istack, icomps);
      then
        (i1,stack,comps);
  end matchcontinue;
end strongConnectMain;

protected function strongConnect "function: strongConnect
  author: PA

  Helper function to strong_connect_main

  inputs:  (IncidenceMatrix, BackendDAE.IncidenceMatrixT, int vector, int vector,
              int /* i */, int /* v */, int list /* stack */, int list list /* components */)
  outputs: (int /* i */, int list /* stack */, int list list /* components */ )
"
  input BackendDAE.IncidenceMatrix m;
  input BackendDAE.IncidenceMatrixT mt;
  input array<Integer> a1;
  input array<Integer> a2;
  input array<Integer> number;
  input array<Integer> lowlink;  
  input Integer inInteger5;
  input Integer inInteger6;
  input list<Integer> inIntegerLst7;
  input list<list<Integer>> inIntegerLstLst8;
  output Integer outInteger;
  output list<Integer> outIntegerLst;
  output list<list<Integer>> outIntegerLstLst;
algorithm
  (outInteger,outIntegerLst,outIntegerLstLst):=
  matchcontinue (m,mt,a1,a2,number,lowlink,inInteger5,inInteger6,inIntegerLst7,inIntegerLstLst8)
    local
      Integer i_1,i,v;
      list<Integer> stack_1,eqns,stack_2,stack_3,comp,stack;
      list<list<Integer>> comps_1,comps_2,comps;
    case (_,_,_,_,_,_,i,v,stack,comps)
      equation
        i_1 = i + 1;
        _ = arrayUpdate(number,v,i_1);
        _ = arrayUpdate(lowlink,v,i_1);
        stack_1 = (v :: stack);
        eqns = reachableNodes(v, m, mt, a1, a2);
        (i_1,stack_2,comps_1) = iterateReachableNodes(eqns, m, mt, a1, a2,number,lowlink, i_1, v, stack_1, comps);
        (stack_3,comp) = checkRoot(v, stack_2,number,lowlink);
        comps_2 = consIfNonempty(comp, comps_1);
      then
        (i_1,stack_3,comps_2);
    else
      equation
        Debug.traceln("- BackendDAETransform.strongConnect failed for eqn " +& intString(inInteger5));
      then
        fail();
  end matchcontinue;
end strongConnect;

protected function consIfNonempty "function: consIfNonempty
  author: PA

  Small helper function to avoid empty sublists.
  Consider moving to Util?
"
  input list<Integer> inIntegerLst;
  input list<list<Integer>> inIntegerLstLst;
  output list<list<Integer>> outIntegerLstLst;
algorithm
  outIntegerLstLst:=
  matchcontinue (inIntegerLst,inIntegerLstLst)
    local
      list<list<Integer>> lst;
      list<Integer> e;
    case ({},lst) then lst;
    case (e,lst) then (e :: lst);
  end matchcontinue;
end consIfNonempty;

public function reachableNodes "function: reachableNodes
  author: PA

  Helper function to strong_connect.
  Returns a list of reachable nodes (equations), corresponding
  to those equations that uses the solved variable of this equation.
  The edges of the graph that identifies strong components/blocks are
  dependencies between blocks. A directed edge e = (n1,n2) means
  that n1 solves for a variable (e.g. \'a\') that is used in the equation
  of n2, i.e. the equation of n1 must be solved before the equation of n2.
"
  input Integer eqn;
  input BackendDAE.IncidenceMatrix m;
  input BackendDAE.IncidenceMatrixT mt;
  input array<Integer> a1;
  input array<Integer> a2;
  output list<Integer> outIntegerLst;
algorithm
  outIntegerLst:=
  matchcontinue (eqn,m,mt,a1,a2)
    local
      Integer var;
      list<Integer> reachable,reachable_1;
      String eqnstr;
    case (_,_,_,_,_)
      equation
        var = a2[eqn];
        reachable = mt[var] "Got the variable that is solved in the equation" ;
        reachable_1 = BackendDAEUtil.removeNegative(reachable) "in which other equations is this variable present ?" ;
      then
        List.removeOnTrue(eqn, intEq, reachable_1);
    else
      equation
        true = Flags.isSet(Flags.FAILTRACE);
        Debug.trace("-reachable_nodes failed, eqn: ");
        eqnstr = intString(eqn);
        Debug.traceln(eqnstr);
      then
        fail();
  end matchcontinue;
end reachableNodes;

protected function iterateReachableNodes "function: iterateReachableNodes
  author: PA

  Helper function to strong_connect.

  inputs:  (int list, BackendDAE.IncidenceMatrix, BackendDAE.IncidenceMatrixT, int vector, int vector,
              int /* i */, int /* v */, int list /* stack */, int list list /* components */)
  outputs: (int /* i */, int list /* stack */, int list list /* components */)
"
  input list<Integer> eqns;
  input BackendDAE.IncidenceMatrix m;
  input BackendDAE.IncidenceMatrixT mt;
  input array<Integer> a1;
  input array<Integer> a2;
  input array<Integer> number;
  input array<Integer> lowlink;   
  input Integer i;
  input Integer v;
  input list<Integer> istack;
  input list<list<Integer>> icomps;
  output Integer outInteger;
  output list<Integer> outIntegerLst;
  output list<list<Integer>> outIntegerLstLst;
algorithm
  (outInteger,outIntegerLst,outIntegerLstLst):=
  matchcontinue (eqns,m,mt,a1,a2,number,lowlink,i,v,istack,icomps)
    local
      Integer i1,lv,lw,minv,w,nw,nv,lowlinkv;
      list<Integer> stack,ws;
      list<list<Integer>> comps_1,comps_2,comps;
    
    // empty case
    case ({},_,_,_,_,_,_,_,_,_,_) then (i,istack,icomps);    
    
    // nw is 0
    case ((w :: ws),_,_,_,_,_,_,_,_,_,_)
      equation
        true = intEq(number[w],0);
        (i1,stack,comps_1) = strongConnect(m, mt, a1, a2, number, lowlink, i, w, istack, icomps);
        lv = lowlink[v];
        lw = lowlink[w];
        minv = intMin(lv, lw);
        _ = arrayUpdate(lowlink,v,minv);
        (i1,stack,comps_2) = iterateReachableNodes(ws, m, mt, a1, a2, number, lowlink, i1, v, stack, comps_1);
      then
        (i1,stack,comps_2);
    
    // nw 
    case ((w :: ws),_,_,_,_,_,_,_,_,_,_)
      equation
        nw = number[w];
        nv = lowlink[v];        
        (nw < nv) = true;
        true = listMember(w, istack);
        lowlinkv = lowlink[v];
        minv = intMin(nw, lowlinkv);
        _ = arrayUpdate(lowlink,v,minv);
        (i1,stack,comps) = iterateReachableNodes(ws, m, mt, a1, a2, number, lowlink, i, v, istack, icomps);
      then
        (i1,stack,comps);

    case ((_ :: ws),_,_,_,_,_,_,i,_,_,_)
      equation
        (i1,stack,comps) = iterateReachableNodes(ws, m, mt, a1, a2, number, lowlink, i, v, istack, icomps);
      then
        (i1,stack,comps);
    
  end matchcontinue;
end iterateReachableNodes;

protected function checkRoot "function: checkRoot
  author: PA

  Helper function to strong_connect.

  inputs:  (int /* v */, int list /* stack */, int vector, int vector)
  outputs: (int list /* stack */, int list /* comps */)
"
  input Integer v;
  input list<Integer> istack;
  input array<Integer> number;
  input array<Integer> lowlink;   
  output list<Integer> ostack;
  output list<Integer> ocomps;
algorithm
  (ostack,ocomps):=
  matchcontinue (v,istack,number,lowlink)
    local
      Integer lv,nv;
      list<Integer> comps,stack;
    case (_,_,_,_)
      equation
        lv = lowlink[v];
        nv = number[v];
        true = intEq(lv,nv);
        (stack,comps) = checkStack(nv, istack, number, {});
      then
        (stack,comps);
    case (_,_,_,_) then (istack,{});
  end matchcontinue;
end checkRoot;

protected function checkStack "function: checkStack
  author: PA

  Helper function to check_root.

  inputs:  (int /* vn */, int list /* stack */, int vector, int list /* component list */)
  outputs: (int list /* stack */, int list /* comps */)
"
  input Integer vn;
  input list<Integer> istack;
  input array<Integer> number;
  input list<Integer> icomp;
  output list<Integer> ostack;
  output list<Integer> ocomp;
algorithm
  (ostack,ocomp):=
  matchcontinue (vn,istack,number,icomp)
    local
      Integer top;
      list<Integer> rest,comp,stack;
    case (_,(top :: rest),_,_)
      equation
        true = intGe(number[top],vn);
        (stack,comp) = checkStack(vn, rest, number, top :: icomp);
      then
        (stack,comp);
    case (_,_,_,_) then (istack,listReverse(icomp));
  end matchcontinue;
end checkStack;

/******************************************
 DAEHandler stuff
 *****************************************/
 
protected function emptyDAEHandlerArg
"function: emptyDAEHandlerArg
  author: Frenkel TUD 2011-05
  returns an empty DAEHandlerArg"
  input array<list<Integer>> mapEqnIncRow;
  input array<Integer> mapIncRowEqn;
  output BackendDAE.DAEHandlerArg arg;
protected
  HashTableCG.HashTable ht;
  HashTable3.HashTable dht; 
algorithm
  ht := HashTableCG.emptyHashTable();
  dht := HashTable3.emptyHashTable();
  arg := (BackendDAE.STATEORDER(ht,dht),{},mapEqnIncRow,mapIncRowEqn);
end emptyDAEHandlerArg;

public function addStateOrder
"function: addStateOrder
  author: Frenkel TUD 2011-05
  add state and state derivative to the 
  stateorder."
  input DAE.ComponentRef cr;
  input DAE.ComponentRef dcr;
  input BackendDAE.StateOrder inStateOrder;
  output BackendDAE.StateOrder outStateOrder;
algorithm
 outStateOrder :=
  matchcontinue (cr,dcr,inStateOrder)
    local
        HashTableCG.HashTable ht,ht1;
        HashTable3.HashTable dht,dht1;  
        list<DAE.ComponentRef> crlst;
    case (_,_,BackendDAE.STATEORDER(ht,dht))
      equation
        ht1 = BaseHashTable.add((cr, dcr),ht);
        failure(_ = getDerStateOrder(dcr,inStateOrder));
        dht1 = BaseHashTable.add((dcr, {cr}),dht); 
      then
       BackendDAE.STATEORDER(ht1,dht1);
    case (_,_,inStateOrder as BackendDAE.STATEORDER(ht,dht))
      equation
        ht1 = BaseHashTable.add((cr, dcr),ht);
        crlst = getDerStateOrder(dcr,inStateOrder);
        dht1 = BaseHashTable.add((dcr, cr::crlst),dht); 
      then
       BackendDAE.STATEORDER(ht1,dht1);
  end matchcontinue;    
end addStateOrder;

public function addAliasStateOrder
"function: addAliasStateOrder
  author: Frenkel TUD 2012-06
  add state and replace alias state in the 
  stateorder."
  input DAE.ComponentRef cr;
  input DAE.ComponentRef acr;
  input BackendDAE.StateOrder inStateOrder;
  output BackendDAE.StateOrder outStateOrder;
algorithm
 outStateOrder :=
  matchcontinue (cr,acr,inStateOrder)
    local
        HashTableCG.HashTable ht,ht1;
        HashTable3.HashTable dht,dht1;   
        DAE.ComponentRef dcr,cr1;
        list<DAE.ComponentRef> crlst;
        Boolean b;
    case (_,_,inStateOrder as BackendDAE.STATEORDER(ht,dht))
      equation
        dcr = BaseHashTable.get(acr,ht);
        failure(_ = BaseHashTable.get(cr,ht));
        ht1 = BaseHashTable.add((cr, dcr),ht);
        {cr1} = BaseHashTable.get(dcr,dht);
        ht1 = BaseHashTable.delete(acr,ht1);
        b = ComponentReference.crefEqualNoStringCompare(cr1, acr);
        crlst = Util.if_(b,{cr},{cr,cr1});
        dht1 = BaseHashTable.add((dcr, crlst),dht); 
      then
        BackendDAE.STATEORDER(ht1,dht1);
        //replaceDerStateOrder(cr,acr,BackendDAE.STATEORDER(ht1,dht1));
    case (_,_,inStateOrder as BackendDAE.STATEORDER(ht,dht))
      equation
        dcr = BaseHashTable.get(acr,ht);
        failure(_ = BaseHashTable.get(cr,ht));
        ht1 = BaseHashTable.add((cr, dcr),ht);
        ht1 = BaseHashTable.delete(acr,ht1);
        crlst = BaseHashTable.get(dcr,dht);
        crlst = List.removeOnTrue(acr,ComponentReference.crefEqualNoStringCompare,crlst);
        dht1 = BaseHashTable.add((dcr, cr::crlst),dht); 
      then
        BackendDAE.STATEORDER(ht1,dht1);
        //replaceDerStateOrder(cr,acr,BackendDAE.STATEORDER(ht1,dht1));
    case (_,_,inStateOrder as BackendDAE.STATEORDER(ht,dht))
      equation
        dcr = BaseHashTable.get(acr,ht);
        _ = BaseHashTable.get(cr,ht);
        {cr1} = BaseHashTable.get(dcr,dht);
        ht1 = BaseHashTable.delete(acr,ht);
        b = ComponentReference.crefEqualNoStringCompare(cr1, acr);
        crlst = Util.if_(b,{cr},{cr,cr1});
        dht1 = BaseHashTable.add((dcr, crlst),dht); 
      then
        BackendDAE.STATEORDER(ht1,dht1);
        //replaceDerStateOrder(cr,acr,BackendDAE.STATEORDER(ht1,dht1));
    case (_,_,inStateOrder as BackendDAE.STATEORDER(ht,dht))
      equation
        dcr = BaseHashTable.get(acr,ht);
        _ = BaseHashTable.get(cr,ht);
        ht1 = BaseHashTable.delete(acr,ht);
        crlst = BaseHashTable.get(dcr,dht);
        crlst = List.removeOnTrue(acr,ComponentReference.crefEqualNoStringCompare,crlst);
        dht1 = BaseHashTable.add((dcr, cr::crlst),dht); 
      then
        BackendDAE.STATEORDER(ht1,dht1);
        //replaceDerStateOrder(cr,acr,BackendDAE.STATEORDER(ht1,dht1));               
    case (_,_,BackendDAE.STATEORDER(hashTable=ht))
      equation
        failure(_ = BaseHashTable.get(acr,ht));
      then
        inStateOrder;
        //replaceDerStateOrder(cr,acr,inStateOrder);
  end matchcontinue;    
end addAliasStateOrder;

protected function replaceDerStateOrder
"function: replaceDerStateOrder
  author: Frenkel TUD 2012-06
  replace a state  in the 
  stateorder."
  input DAE.ComponentRef cr;
  input DAE.ComponentRef acr;
  input BackendDAE.StateOrder inStateOrder;
  output BackendDAE.StateOrder outStateOrder;
algorithm
 outStateOrder :=
  matchcontinue (cr,acr,inStateOrder)
    local
        HashTableCG.HashTable ht,ht1;
        HashTable3.HashTable dht,dht1;   
        DAE.ComponentRef cr1;
        list<DAE.ComponentRef> crlst;
        list<tuple<DAE.ComponentRef,DAE.ComponentRef>> crcrlst;
        Boolean b;
    case (_,_,BackendDAE.STATEORDER(ht,dht))
      equation
        {cr1} = BaseHashTable.get(acr,dht);
        ht1 = BaseHashTable.add((cr1, cr),ht); 
        BackendDump.debugStrCrefStrCrefStr(("replac der Alias State ",cr1," -> ",cr,"\n"));
      then
       BackendDAE.STATEORDER(ht1,dht);
    case (_,_,BackendDAE.STATEORDER(ht,dht))
      equation
        crlst = BaseHashTable.get(acr,dht);
        crcrlst = List.map1(crlst,Util.makeTuple,cr);
        ht1 = List.fold(crcrlst,BaseHashTable.add,ht);
        BackendDump.debugStrCrefStrCrefStr(("replac der Alias State ",acr," -> ",cr,"\n"));
      then
       BackendDAE.STATEORDER(ht1,dht);                     
    case (_,_,BackendDAE.STATEORDER(invHashTable=dht))
      equation
        failure(_ = BaseHashTable.get(acr,dht));
      then
       inStateOrder;
  end matchcontinue;    
end replaceDerStateOrder;

public function getStateOrder
"function: getStateOrder
  author: Frenkel TUD 2011-05
  returns the derivative of a state.
  Fails if there is none"
  input DAE.ComponentRef cr;
  input BackendDAE.StateOrder inStateOrder;
  output DAE.ComponentRef dcr;
protected
  HashTableCG.HashTable ht;
algorithm
  BackendDAE.STATEORDER(hashTable=ht) := inStateOrder;
  dcr := BaseHashTable.get(cr,ht);
end getStateOrder;

public function getDerStateOrder
"function: getDerStateOrder
  author: Frenkel TUD 2011-05
  returns the states of a state derivative.
  Fails if there is none"
  input DAE.ComponentRef dcr;
  input BackendDAE.StateOrder inStateOrder;
  output list<DAE.ComponentRef> crlst;
protected
  HashTable3.HashTable dht;  
algorithm
  BackendDAE.STATEORDER(invHashTable=dht) := inStateOrder;
  crlst := BaseHashTable.get(dcr,dht);
end getDerStateOrder;

public function addOrgEqn
"function: addOrgEqn
  author: Frenkel TUD 2011-05
  add an equation to the ConstrainEquations."
  input BackendDAE.ConstraintEquations inOrgEqns;
  input Integer e;
  input BackendDAE.Equation inEqn;
  output BackendDAE.ConstraintEquations outOrgEqns;
algorithm
  outOrgEqns :=
  matchcontinue (inOrgEqns,e,inEqn)
    local
      list<BackendDAE.Equation> orgeqns;
      Integer e1;
      BackendDAE.ConstraintEquations rest,orgeqnslst;
    
    case ({},_,_) then {(e,{inEqn})};
    case ((e1,orgeqns)::rest,e,inEqn)
      equation
        true = intGt(e1,e);
      then
        (e,{inEqn})::inOrgEqns;
    case ((e1,orgeqns)::rest,_,_)
      equation
        true = intEq(e1,e);
      then
        (e1,inEqn::orgeqns)::rest;     
    case ((e1,orgeqns)::rest,_,_)
      equation
        orgeqnslst = addOrgEqn(rest,e,inEqn);
      then
        (e1,orgeqns)::orgeqnslst;            
  end matchcontinue;
end addOrgEqn;

public function getOrgEqn
"function: getOrgEqn
  author: Frenkel TUD 2011-05
  returns the first equation of each orgeqn list."
  input list<tuple<Integer,list<tuple<Integer,Integer,Boolean>>>> inOrgEqns;
  input list<tuple<Integer,Integer,Integer>> inOrgEqnLevel;
  output list<tuple<Integer,list<tuple<Integer,Integer,Boolean>>>> outOrgEqns;
  output list<tuple<Integer,Integer,Integer>> outOrgEqnLevel;
algorithm
  (outOrgEqns,outOrgEqnLevel) :=
  matchcontinue (inOrgEqns,inOrgEqnLevel)
    local
      list<tuple<Integer,Integer,Boolean>> orgeqn;
      Integer e,ep,l;
      Boolean b;
      list<tuple<Integer,list<tuple<Integer,Integer,Boolean>>>> rest,orgeqns;
      list<tuple<Integer,Integer,Integer>> orgEqnLevel;
    
    case ({},inOrgEqnLevel) then ({},inOrgEqnLevel);
    case ((e,(ep,l,false)::{})::rest,inOrgEqnLevel)
      equation
        (orgeqns,orgEqnLevel) = getOrgEqn(rest,(e,ep,l)::inOrgEqnLevel);
      then
        (orgeqns,orgEqnLevel);      
    case ((e,(ep,l,true)::{})::rest,inOrgEqnLevel)
      equation
        (orgeqns,orgEqnLevel) = getOrgEqn(rest,inOrgEqnLevel);
      then
        (orgeqns,orgEqnLevel);      
    case ((e,(ep,l,false)::orgeqn)::rest,inOrgEqnLevel)
      equation
        (orgeqns,orgEqnLevel) = getOrgEqn(rest,(e,ep,l)::inOrgEqnLevel);
      then
        ((e,orgeqn)::orgeqns,orgEqnLevel);
    case ((e,(ep,l,true)::orgeqn)::rest,inOrgEqnLevel)
      equation
        (orgeqns,orgEqnLevel) = getOrgEqn(rest,inOrgEqnLevel);
      then
        ((e,orgeqn)::orgeqns,orgEqnLevel);
  end matchcontinue;
end getOrgEqn;

public function dumpStateOrder
"function: dumpStateOrder
  author: Frenkel TUD 2011-05
  Prints the state order"
  input BackendDAE.StateOrder inStateOrder;
algorithm
  _:=
  match (inStateOrder)
    local
      String str,len_str;
      Integer len;
      HashTableCG.HashTable ht;
      HashTable3.HashTable dht;
      list<tuple<DAE.ComponentRef,DAE.ComponentRef>> tplLst;
    case (BackendDAE.STATEORDER(ht,dht))
      equation
        print("State Order: (");
        (tplLst) = BaseHashTable.hashTableList(ht);
        str = stringDelimitList(List.map(tplLst,printStateOrderStr),"\n");
        len = listLength(tplLst);
        len_str = intString(len);
        print(len_str);
        print(")\n");
        print("=============\n");
        print(str);
        print("\n");
      then
        ();
  end match;
end dumpStateOrder;

protected function printStateOrderStr "help function to dumpStateOrder"
  input tuple<DAE.ComponentRef,DAE.ComponentRef> tpl;
  output String str;
algorithm
  str := ComponentReference.printComponentRefStr(Util.tuple21(tpl)) +& " -> " +& ComponentReference.printComponentRefStr(Util.tuple22(tpl));
end printStateOrderStr;

public function replaceStateOrderExp
"function: replaceStateExp
  author: Frenkel TUD 2011-05"
  input tuple<DAE.Exp,BackendDAE.StateOrder> inTpl;
  output tuple<DAE.Exp,BackendDAE.StateOrder> outTpl;
protected
  DAE.Exp e;
  BackendDAE.StateOrder so;
algorithm
  (e,so) := inTpl;
  outTpl := Expression.traverseExp(e,replaceStateOrderExpFinder,so);
end replaceStateOrderExp;

protected function replaceStateOrderExpFinder
"function: replaceStateOrderExpFinder
  author: Frenkel TUD 2011-05 "
  input tuple<DAE.Exp,BackendDAE.StateOrder> inExp;
  output tuple<DAE.Exp,BackendDAE.StateOrder> outExp;
algorithm
  (outExp) := matchcontinue (inExp)
    local
      DAE.Exp e;
      BackendDAE.StateOrder so;
      DAE.ComponentRef dcr,cr;
      String ident;
     case ((DAE.CALL(path = Absyn.IDENT(name = "der"),expLst = {DAE.CREF(componentRef = cr)}),so))
      equation
        dcr = getStateOrder(cr,so);
        e = Expression.crefExp(dcr);
      then
        ((e,so));
        
     case ((DAE.CREF(componentRef = DAE.CREF_QUAL(ident=ident,subscriptLst={},componentRef=cr)),so))
      equation
        true = stringEq(ident,DAE.derivativeNamePrefix);
        dcr = getStateOrder(cr,so);
        e = Expression.crefExp(dcr);
      then
        ((e,so));        
        
     else then (inExp);
  end matchcontinue;
end replaceStateOrderExpFinder;


/*****************************************
 reduceIndexDynamicStateSelection and stuff
 *****************************************/

public function traverseStateOrderFinder
"function: traverseStateOrderFinder
  author: Frenkel TUD 2011-05
  collect all states and there derivatives"
 input tuple<BackendDAE.Equation, tuple<BackendDAE.StateOrder,BackendDAE.Variables>> inTpl;
 output tuple<BackendDAE.Equation, tuple<BackendDAE.StateOrder,BackendDAE.Variables>> outTpl;
algorithm
  outTpl:=
  matchcontinue (inTpl)
    local
      BackendDAE.Equation e;
      BackendDAE.StateOrder so,so1;
      BackendDAE.Variables v;
      DAE.ComponentRef cr,dcr;
    case ((e,(so,v)))
      equation
        (cr,dcr,_,_,false) = BackendEquation.derivativeEquation(e);
        true = BackendVariable.isState(cr,v);
        so1 = addStateOrder(cr,dcr,so);
      then ((e,(so1,v)));
    case inTpl then inTpl;
  end matchcontinue;
end traverseStateOrderFinder;


public function collectVarEqns
"function: collectVarEqns
  author: Frenkel TUD 2011-05
  collect all equations of a list with var indexes"
  input list<Integer> inIntegerLst1;
  input list<Integer> inIntegerLst2;
  input BackendDAE.IncidenceMatrixT inMT;
  input Integer inArrayLength;
  output list<Integer> outIntegerLst;
algorithm
  outIntegerLst := matchcontinue (inIntegerLst1,inIntegerLst2,inMT,inArrayLength)
    local
      BackendDAE.IncidenceMatrixT mt;
      Integer i,l;
      list<Integer> rest,eqns,ilst,ilst1; 
    case ({},inIntegerLst2,_,_)
      then 
        inIntegerLst2;
    case (i::rest,inIntegerLst2,mt,l)
      equation
        true = intLt(i,l);
        eqns = List.map(mt[i],intAbs);
        ilst = List.union(eqns,inIntegerLst2);
        ilst1 = collectVarEqns(rest,ilst,mt,l);  
      then 
        ilst1;
    case (i::rest,inIntegerLst2,mt,l)
      equation
        ilst1 = collectVarEqns(rest,inIntegerLst2,mt,l);  
      then 
        ilst1;        
    case (i::rest,inIntegerLst2,mt,l)
      equation
        print("collectVarEqns failed for eqn " +& intString(i) +& "\n");
      then fail();
  end matchcontinue;
end collectVarEqns;

public function sortStateCandidatesVars
"function: sortStateCandidatesVars
  author: Frenkel TUD 2012-05
  sort the state candidates"
  input BackendDAE.EqSystem syst;
  input array<Integer> mapIncRowEqn;
  input BackendDAE.StateOrder so;
  output BackendDAE.Variables outStates;
algorithm
  outStates:=
  matchcontinue (syst,mapIncRowEqn,so)
    local
      list<DAE.ComponentRef> varCrefs;
      list<Integer> varIndices;
      BackendDAE.Variables vars,states;
      BackendDAE.IncidenceMatrix m;
      BackendDAE.IncidenceMatrixT mt;
      BackendDAE.EquationArray eqns;
      list<tuple<DAE.ComponentRef,Integer,Real>> prioTuples;
      list<BackendDAE.Var> vlst;

    case (BackendDAE.EQSYSTEM(orderedVars=vars,orderedEqs = eqns,m=SOME(m),mT=SOME(mt)),_,_)
      equation
        varCrefs = List.map(BackendDAEUtil.varList(vars),BackendVariable.varCref);
        varIndices = List.intRange(listLength(varCrefs));
        prioTuples = calculateVarPriorities(varCrefs,varIndices,vars,eqns,m,mt,mapIncRowEqn,so,{});
        prioTuples = List.sort(prioTuples,sortprioTuples);
        varIndices = List.map(prioTuples,Util.tuple32);
        vlst = List.map1r(varIndices,BackendVariable.getVarAt,vars);
        states = BackendDAEUtil.listVar1(vlst);
      then states;

    else
      equation
        print("Error, sortStateCandidatesVars failed!");
      then
        fail();

  end matchcontinue;
end sortStateCandidatesVars;

public function sortStateCandidates
"function: sortStateCandidates
  author: Frenkel TUD 2011-05
  sort the state candidates"
  input list<tuple<DAE.ComponentRef,Integer>> inStates;
  input BackendDAE.EqSystem syst;
  input BackendDAE.StateOrder so;
  output list<tuple<DAE.ComponentRef,Integer>> outStates;
algorithm
  outStates:=
  matchcontinue (inStates,syst,so)
    local
      list<DAE.ComponentRef> varCrefs;
      list<Integer> varIndices;
      BackendDAE.Variables vars;
      BackendDAE.IncidenceMatrix m;
      BackendDAE.IncidenceMatrixT mt;
      BackendDAE.EquationArray eqns;
      list<tuple<DAE.ComponentRef,Integer,Real>> prioTuples;
      list<tuple<DAE.ComponentRef,Integer>> states;

    case (_,BackendDAE.EQSYSTEM(orderedVars=vars,orderedEqs = eqns,m=SOME(m),mT=SOME(mt)),_)
      equation
        varCrefs = List.map(inStates,Util.tuple21);
        varIndices = List.map(inStates,Util.tuple22);
        prioTuples = calculateVarPriorities(varCrefs,varIndices,vars,eqns,m,mt,listArray({}),so,{});
        prioTuples = List.sort(prioTuples,sortprioTuples);
        states = List.map(prioTuples,Util.tuple312);
      then states;

    case ({},_,_)
      equation
        print("Error, sortStateCandidates:");
        //dump(dae);
      then
        fail();

  end matchcontinue;
end sortStateCandidates;

protected function sortprioTuples
"function: sortprioTuples
  author: Frenkel TUD 2011-05
  helper for sortStateCandidates"
  input tuple<DAE.ComponentRef,Integer,Real> inTpl1;
  input tuple<DAE.ComponentRef,Integer,Real> inTpl2;
  output Boolean b;
algorithm
  b:= realGt(Util.tuple33(inTpl1),Util.tuple33(inTpl2));
end sortprioTuples;

public function makeDummyState "function: makeDummyState
  author: Frenkel TUD 20-11"
  input DAE.ComponentRef dummystate;
  input Integer stateindx;
  input BackendDAE.EqSystem isyst;
  input BackendDAE.Shared ishared;
  input array<Integer> mapIncRowEqn;
  output DAE.ComponentRef outDerDummyState;
  output BackendDAE.EqSystem osyst;
  output BackendDAE.Shared oshared;
  output list<Integer> ochangedeqns;
algorithm
  (outDerDummyState,osyst,oshared,ochangedeqns) := 
   matchcontinue (dummystate,stateindx,isyst,ishared,mapIncRowEqn)
    local
      list<Integer> changedeqns;
      DAE.ComponentRef dummy_der;
      DAE.Exp stateexp,stateexpcall,dummyderexp;
      BackendDAE.IncidenceMatrixT mt;
      BackendDAE.EqSystem syst;
      BackendDAE.Shared shared;

    case (dummystate,stateindx,syst as BackendDAE.EQSYSTEM(mT=SOME(mt)),_,_)
      equation
        (dummy_der,syst) = newDummyVar(dummystate, syst, DAE.NEW_DUMMY_DER(dummystate,{}));
        Debug.fcall(Flags.BLT_DUMP, BackendDump.debugStrCrefStr, ("Chosen dummy: ",dummy_der," as dummy state\n"));
        changedeqns = BackendDAEUtil.eqnsForVarWithStates(mt, stateindx);
        stateexp = Expression.crefExp(dummystate);
        stateexpcall = DAE.CALL(Absyn.IDENT("der"),{stateexp},DAE.callAttrBuiltinReal);
        dummyderexp = Expression.crefExp(dummy_der);
        changedeqns = List.unique(List.map1r(changedeqns,arrayGet,mapIncRowEqn));        
        (syst,shared) = replaceDummyDer(stateexpcall, dummyderexp, syst, ishared, changedeqns)
        "We need to change variables in the differentiated equations and in the equations having the dummy derivative" ;
        syst = makeAlgebraic(syst, dummystate);
      then
        (dummy_der,syst,ishared,changedeqns);
    else
      equation
         print("BackendDAETransform.makeDummyState failed\n");
      then fail();
  end matchcontinue;
end makeDummyState;

public function dumpEqnsX
"function: dumpEqnsX
  author: Frenkel TUD"
  input BackendDAE.ConstraintEquations orgEqns;
algorithm
  _:=
  matchcontinue (orgEqns)
    local
      list<BackendDAE.Equation> orgeqns;
      BackendDAE.ConstraintEquations rest;
      Integer i;
    case ({}) then ();
    case ((i,orgeqns)::rest)
      equation
        print("OrgEqns: "); print(intString(i)); print("\n");
        dumpEqnsX1(orgeqns);
        dumpEqnsX(rest);
      then
        ();
  end matchcontinue;
end dumpEqnsX;

protected function dumpEqnsX1
"function: dumpEqnsX
  author: Frenkel TUD"
  input list<BackendDAE.Equation> orgEqns;
algorithm
  _:=
  match (orgEqns)
    local
      BackendDAE.Equation orgeqn;
      list<BackendDAE.Equation> rest;
      DAE.Exp exp1,exp2;
      Integer i;
    case ({}) then ();
    case (orgeqn::rest)
      equation
        print("  "); print(BackendDump.equationStr(orgeqn)); print("\n");         
        dumpEqnsX1(rest);
      then
        ();
  end match;
end dumpEqnsX1;

public function dumpEqns1X
"function: dumpEqns1X
  author: Frenkel TUD"
  input tuple<list<tuple<Integer,list<tuple<Integer,Integer,Boolean>>>>,BackendDAE.EqSystem,BackendDAE.Shared> orgEqns;
algorithm
  _:=
  match (orgEqns)
    local
      list<tuple<Integer,Integer,Boolean>> orgeqns;
      list<tuple<Integer,list<tuple<Integer,Integer,Boolean>>>> rest;
      Integer i;
      BackendDAE.EqSystem syst;
      BackendDAE.Shared shared;
    case (({},_,_)) then ();
    case (((i,orgeqns)::rest,syst,shared))
      equation
        print("OrgEqns: "); print(intString(i)); print("\n");
        dumpEqns1X1(orgeqns,syst,shared);
        dumpEqns1X((rest,syst,shared));
      then
        ();
  end match;
end dumpEqns1X;

protected function dumpEqns1X1
"function: dumpEqns1X1
  author: Frenkel TUD"
  input list<tuple<Integer,Integer,Boolean>> orgEqns;
  input BackendDAE.EqSystem syst;
  input BackendDAE.Shared shared;
algorithm
  _:=
  match (orgEqns,syst,shared)
    local
      BackendDAE.Equation orgeqn;
      list<tuple<Integer,Integer,Boolean>> rest;
      BackendDAE.EquationArray eqns;
      DAE.Exp exp1,exp2;
      Integer i,e,l,e_1;
    case ({},_,_) then ();
    case ((e,l,_)::rest,syst as BackendDAE.EQSYSTEM(orderedEqs=eqns),shared)
      equation
        e_1 = e - 1;
        orgeqn = BackendDAEUtil.equationNth(eqns, e_1); 
        print("  "); print(intString(l)); print("  ");  print(BackendDump.equationStr(orgeqn)); print("\n");         
        dumpEqns1X1(rest,syst,shared);
      then
        ();
  end match;
end dumpEqns1X1;

public function dumpStates
"function: dumpStates
  author: Frenkel TUD"
  input tuple<DAE.ComponentRef,Integer> state;
  output String outStr;
algorithm
  outStr := intString(Util.tuple22(state)) +& " " +& ComponentReference.printComponentRefStr(Util.tuple21(state));
end dumpStates;

public function dumpStates1
"function: dumpStates
  author: Frenkel TUD"
  input tuple<DAE.ComponentRef,Integer,DAE.Exp> state;
  output String outStr;
algorithm
  outStr := intString(Util.tuple32(state)) +& " " +& ComponentReference.printComponentRefStr(Util.tuple31(state)) +& " " +& ExpressionDump.printExpStr(Util.tuple33(state));
end dumpStates1;

/******************************************
 reduceIndexDummyDer and stuff
 *****************************************/

public function reduceIndexDummyDer
"function: reduceIndexDummyDer
  author: PA
  When matching fails, this function is called to try to
  reduce the index by differentiating the marked equations and
  replacing one of the variable with a dummy derivative, i.e. making
  it algebraic.
  The new BackendDAE.BackendDAE is returned along with an updated incidence matrix.

  inputs: (BackendDAE, BackendDAE.IncidenceMatrix, BackendDAE.IncidenceMatrixT,
             int /* number of vars */, int /* number of eqns */, int /* i */)
  outputs: (BackendDAE, BackendDAE.IncidenceMatrix, IncidenceMatrixT)"
  input list<Integer> eqns;
  input Integer actualEqn;
  input BackendDAE.EqSystem isyst;
  input BackendDAE.Shared ishared;
  input array<Integer> inAssignments1;
  input array<Integer> inAssignments2;
  input BackendDAE.StructurallySingularSystemHandlerArg inArg;
  output list<Integer> changedEqns;
  output Integer continueEqn;
  output BackendDAE.EqSystem osyst;
  output BackendDAE.Shared oshared;
  output array<Integer> outAssignments1;
  output array<Integer> outAssignments2;
  output BackendDAE.StructurallySingularSystemHandlerArg outArg;
algorithm
  (changedEqns,continueEqn,osyst,oshared,outAssignments1,outAssignments2,outArg):=
  matchcontinue (eqns,actualEqn,isyst,ishared,inAssignments1,inAssignments2,inArg)
    local
      list<Integer> eqns1,diff_eqns,eqns_1,stateindx,deqns,reqns,changedeqns;
      list<DAE.ComponentRef> states;
      array<list<Integer>> mt;
      Integer stateno;
      DAE.ComponentRef state,dummy_der;
      list<String> es;
      String es_1;
      DAE.Exp stateexp,stateexpcall,dummyderexp;
      array<Integer> ass1,ass2;
      BackendDAE.EqSystem syst;
      BackendDAE.Shared shared;
      BackendDAE.StateOrder so,so1;
      BackendDAE.ConstraintEquations orgEqnsLst,orgEqnsLst1;  
      array<list<Integer>> mapEqnIncRow;
      array<Integer> mapIncRowEqn;

    case (eqns,_,syst as BackendDAE.EQSYSTEM(mT=SOME(mt)),shared,ass1,ass2,(so,orgEqnsLst,mapEqnIncRow,mapIncRowEqn))
      equation
        // get from scalar eqns indexes the indexes in the equation array
        eqns1 = List.map1r(eqns,arrayGet,mapIncRowEqn);
        eqns1 = List.unique(eqns1);
        // BackendDump.dumpStateVariables(BackendVariable.daeVars(syst));
        // print("marked equations:");print(stringDelimitList(List.map(eqns,intString),","));print("\n");
        diff_eqns = BackendDAEEXT.getDifferentiatedEqns();
        eqns_1 = List.setDifferenceOnTrue(eqns1, diff_eqns, intEq);
        // print("differentiating equations: ");print(stringDelimitList(List.map(eqns_1,intString),","));print("\n");
        // print(BackendDump.dumpMarkedEqns(syst, eqns_1));

        // Collect the states in the equations that are singular, i.e. composing a constraint between states.
        // Note that states are collected from -all- marked equations, not only the differentiated ones.
        (states,stateindx) = statesInEqns(eqns, syst,{},{});
        (syst,shared,deqns,so1,orgEqnsLst1) = differentiateEqns(syst,shared,eqns_1,so,orgEqnsLst);
        (state,stateno) = selectDummyState(states, stateindx, syst, mapIncRowEqn, so);
        // print("Selected ");print(ComponentReference.printComponentRefStr(state));print(" as dummy state\n");
        // print(" From candidates: ");print(stringDelimitList(List.map(states,ComponentReference.printComponentRefStr),", "));print("\n");
        (dummy_der,syst) = newDummyVar(state, syst, DAE.NEW_DUMMY_DER(state,states));
        // print("Chosen dummy: ");print(ComponentReference.printComponentRefStr(dummy_der));print("\n");
        Debug.fcall(Flags.BLT_DUMP, BackendDump.debugStrCrefStr, ("Selected ",dummy_der," as dummy state\n"));
        reqns = BackendDAEUtil.eqnsForVarWithStates(mt, stateno);
        reqns = List.map1r(reqns,arrayGet,mapIncRowEqn);
        reqns = List.unique(reqns);        
        changedeqns = List.unionOnTrue(deqns, reqns, intEq);
        stateexp = Expression.crefExp(state);
        stateexpcall = DAE.CALL(Absyn.IDENT("der"),{stateexp},DAE.callAttrBuiltinReal);
        dummyderexp = Expression.crefExp(dummy_der);
        (syst,shared) = replaceDummyDer(stateexpcall, dummyderexp, syst, shared, changedeqns)
        "We need to change variables in the differentiated equations and in the equations having the dummy derivative" ;
        syst = makeAlgebraic(syst, state);
        (syst,mapEqnIncRow,mapIncRowEqn) = BackendDAEUtil.updateIncidenceMatrixScalar(syst,BackendDAE.SOLVABLE(), changedeqns,mapEqnIncRow,mapIncRowEqn);
        // print("new DAE:");
        // BackendDump.dumpEqSystem(syst);
        // BackendDump.dump(BackendDAE.DAE({syst},shared));
        // print("new IM:");
        // (_,m,_) = BackendDAEUtil.getIncidenceMatrixfromOption(syst,BackendDAE.SOLVABLE());
        // BackendDump.dumpIncidenceMatrix(m);
        // BackendDump.dumpStateVariables(BackendVariable.daeVars(syst));
      then
        (changedeqns,actualEqn,syst,shared,ass1,ass2,(so1,orgEqnsLst1,mapEqnIncRow,mapIncRowEqn));

    case (eqns,_,syst,shared,_,_,(_,_,_,mapIncRowEqn))
      equation
        // get from scalar eqns indexes the indexes in the equation array
        eqns1 = List.map1r(eqns,arrayGet,mapIncRowEqn);
        eqns1 = List.unique(eqns1);        
        diff_eqns = BackendDAEEXT.getDifferentiatedEqns();
        eqns_1 = List.setDifferenceOnTrue(eqns1, diff_eqns, intEq);
        es = List.map(eqns_1, intString);
        es_1 = stringDelimitList(es, ", ");
        print("eqns =");print(es_1);print("\n");
        ({},_) = statesInEqns(eqns, syst,{},{});
        print("no states found in equations:");
        BackendDump.printEquations(eqns_1, syst);
        print("differentiated equations:");
        BackendDump.printEquations(diff_eqns,syst);
        print("Variables :");
        print(stringDelimitList(List.map(BackendDAEEXT.getMarkedVariables(),intString),", "));
        print("\n");
      then
        fail();

    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR, {"- BackendDAETransform.reduceIndexDummyDer failed!"});
      then
        fail();

  end matchcontinue;
end reduceIndexDummyDer;

protected function checkAssignment
  input Integer indx;
  input Integer ne;
  input array<Integer> ass1;
  input array<Integer> ass2;
  input array<Integer> ass3;
  input list<Integer> inUnassigned;
  output list<Integer> outUnassigned;
algorithm
  outUnassigned := matchcontinue(indx,ne,ass1,ass2,ass3,inUnassigned)
    local 
      Integer r,c;
      list<Integer> unassigned;
    case (_,_,_,_,_,_)
      equation
        true = intGt(indx,ne);
      then
        inUnassigned;
    case (_,_,_,_,_,_)
      equation
        r = ass2[indx];
        print(intString(indx) +& ": " +& intString(r) +& "\n"); 
        print(intString(ass3[indx]) +& "\n");
        _ = arrayUpdate(ass3,indx,r);
        unassigned = List.consOnTrue(intLt(r,0), indx, inUnassigned);
      then
        checkAssignment(indx+1,ne,ass1,ass2,ass3,unassigned);
  end matchcontinue;
end checkAssignment;

protected function makeAlgebraic
"function: makeAlgebraic
  author: PA
  Make the variable a dummy derivative, i.e.
  change varkind from STATE to DUMMY_STATE.
  inputs:  (BackendDAE, DAE.ComponentRef /* state */)
  outputs: (BackendDAE) = "
  input BackendDAE.EqSystem syst;
  input DAE.ComponentRef inComponentRef;
  output BackendDAE.EqSystem osyst;
algorithm
  osyst := matchcontinue (syst,inComponentRef)
    local
      DAE.ComponentRef cr;
      BackendDAE.VarKind kind;
      DAE.VarDirection d;
      DAE.VarParallelism prl;
      BackendDAE.Type t;
      Option<DAE.Exp> b;
      Option<Values.Value> value;
      list<DAE.Subscript> dim;
      DAE.ElementSource source;
      Option<DAE.VariableAttributes> dae_var_attr;
      Option<SCode.Comment> comment;
      DAE.ConnectorType ct;
      list<Integer> indx;
      BackendDAE.Variables vars_1,vars;
      BackendDAE.EquationArray e;
      Option<BackendDAE.IncidenceMatrix> om,omT;
      BackendDAE.Matching matching;

    case (BackendDAE.EQSYSTEM(vars,e,om,omT,matching),cr)
      equation
        ((BackendDAE.VAR(cr,kind,d,prl,t,b,value,dim,source,dae_var_attr,comment,ct) :: _),indx) = BackendVariable.getVar(cr, vars);
        vars_1 = BackendVariable.addVar(BackendDAE.VAR(cr,BackendDAE.DUMMY_STATE(),d,prl,t,b,value,dim,source,dae_var_attr,comment,ct), vars);
      then
        BackendDAE.EQSYSTEM(vars_1,e,om,omT,matching);

    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR, {"- BackendDAETransform.makeAlgebraic failed!"});
      then
        fail();

  end matchcontinue;
end makeAlgebraic;

protected function propagateDummyFixedAttribute
"function: propagateDummyFixedAttribute
  author: PA
  This function takes a list of equations that are differentiated
  and the chosen dummy state.
  The fixed attribute of the selected dummy state is propagated to
  the other state. This must be done since the dummy state becomes
  an algebraic state which has fixed = false by default.
  For example consider the equations:
  s1 = b;
  b=2c;
  c = s2;
  if s2 is selected as dummy derivative and s2 has an initial equation
  i.e. fixed should be false for the state s2 (which is set by the user),
  this fixed value has to be propagated to s1 when s2 becomes a dummy
  state."
  input BackendDAE.EqSystem syst;
  input list<Integer> inIntegerLst;
  input DAE.ComponentRef inComponentRef;
  input Integer inInteger;
  output BackendDAE.EqSystem osyst;
algorithm
  osyst := matchcontinue (syst,inIntegerLst,inComponentRef,inInteger)
    local
      list<Integer> eqns;
      list<BackendDAE.Equation> eqns_lst;
      list<DAE.ComponentRef> crefs;
      DAE.ComponentRef state,dummy;
      BackendDAE.Var v,v_1,v_2;
      Integer indx,indx_1,dummy_no;
      Boolean dummy_fixed;
      BackendDAE.Variables vars_1,vars,kv,ev,av;
      BackendDAE.BackendDAE dae;
      BackendDAE.EquationArray e,se,ie;
      BackendDAE.EventInfo ei;
      BackendDAE.ExternalObjectClasses eoc;
      Option<BackendDAE.IncidenceMatrix> om,omT;
      BackendDAE.Matching matching;

   /* eqns dummy state */
    case (BackendDAE.EQSYSTEM(vars,e,om,omT,matching),eqns,dummy,dummy_no)
      equation
        eqns_lst = BackendEquation.getEqns(eqns,e);
        crefs = BackendEquation.equationsCrefs(eqns_lst);
        (crefs, _) = List.deleteMemberOnTrue(dummy, crefs, ComponentReference.crefEqualNoStringCompare);
        state = findState(vars, crefs);
        ({v},{indx}) = BackendVariable.getVar(dummy, vars);
        (dummy_fixed as false) = BackendVariable.varFixed(v);
        ({v_1},{indx_1}) = BackendVariable.getVar(state, vars);
        v_2 = BackendVariable.setVarFixed(v_1, dummy_fixed);
        vars_1 = BackendVariable.addVar(v_2, vars);
      then
        BackendDAE.EQSYSTEM(vars_1,e,om,omT,matching);

    // Never propagate fixed=true
    case (syst as BackendDAE.EQSYSTEM(vars,e,om,omT,matching),eqns,dummy,dummy_no)
      equation
        eqns_lst = BackendEquation.getEqns(eqns,e);
        crefs = BackendEquation.equationsCrefs(eqns_lst);
        (crefs, _) = List.deleteMemberOnTrue(dummy, crefs, ComponentReference.crefEqualNoStringCompare);
        state = findState(vars, crefs);
        ({v},{indx}) = BackendVariable.getVar(dummy, vars);
        true = BackendVariable.varFixed(v);
      then syst;

    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR,{"propagateDummyFixedAttribute"});
      then fail();

  end matchcontinue;
end propagateDummyFixedAttribute;

protected function findState
"function: findState
  author: PA
  Returns the first state from a list of component references."
  input BackendDAE.Variables inVariables;
  input list<DAE.ComponentRef> inExpComponentRefLst;
  output DAE.ComponentRef outComponentRef;
algorithm
  outComponentRef:=
  matchcontinue (inVariables,inExpComponentRefLst)
    local
      BackendDAE.Var v;
      BackendDAE.Variables vars;
      DAE.ComponentRef cr;
      list<DAE.ComponentRef> crs;

    case (vars,(cr :: crs))
      equation
        ((v :: _),_) = BackendVariable.getVar(cr, vars);
        BackendDAE.STATE() = BackendVariable.varKind(v);
      then
        cr;

    case (vars,(cr :: crs))
      equation
        cr = findState(vars, crs);
      then
        cr;

  end matchcontinue;
end findState;

protected function replaceDummyDer
"function: replaceDummyDer
  author: PA
  Helper function to reduceIndexDummyDer
  replaces der(state) with the variable dummy der.
  inputs:   (DAE.ComponentRef, /* state */
             DAE.ComponentRef, /* dummy der name */
             BackendDAE,
             IncidenceMatrix,
             IncidenceMatrixT,
             int list /* equations */)
  outputs:  (BackendDAE,
             IncidenceMatrix,
             IncidenceMatrixT)"
  input DAE.Exp inExp1;
  input DAE.Exp inExp2;
  input BackendDAE.EqSystem isyst;
  input BackendDAE.Shared ishared;
  input list<Integer> inIntegerLst6;
  output BackendDAE.EqSystem osyst;
  output BackendDAE.Shared oshared;
algorithm
  (osyst,oshared):=
  matchcontinue (inExp1,inExp2,isyst,ishared,inIntegerLst6)
    local
      Option<array<list<Integer>>> m,mt;
      Integer e_1,e;
      BackendDAE.Equation eqn,eqn_1;
      BackendDAE.Variables v_1,v,kv,ev,av;
      BackendDAE.EquationArray eqns_1,eqns,seqns,seqns1,ie,ie1;
      array<DAE.Constraint> constrs;
      array<DAE.ClassAttributes> clsAttrs;
      Env.Cache cache;
      Env.Env env;      
      DAE.FunctionTree funcs;
      list<BackendDAE.WhenClause> wclst;
      list<BackendDAE.ZeroCrossing> zeroCrossingLst;
      list<Integer> rest;
      BackendDAE.ExternalObjectClasses eoc;
      BackendDAE.SymbolicJacobians symjacs;
      DAE.Exp stateexpcall,dummyderexp;
      BackendDAE.BackendDAEType btp;
      BackendDAE.Matching matching;
      BackendDAE.EqSystem syst;
      BackendDAE.Shared shared;
      
      list<DAE.ComponentRef> crlst;
      
    case (stateexpcall,dummyderexp,BackendDAE.EQSYSTEM(v,eqns,m,mt,matching),BackendDAE.SHARED(kv,ev,av,ie,seqns,constrs,clsAttrs,cache,env,funcs,BackendDAE.EVENT_INFO(wclst,zeroCrossingLst),eoc,btp,symjacs),{})
      equation
        (av,(_, _)) = BackendVariable.traverseBackendDAEVarsWithUpdate(av,traverseReplaceAliasVarsBindExp,(stateexpcall, dummyderexp));
        (ie1,(_,_)) = BackendEquation.traverseBackendDAEEqnsWithUpdate(ie,traversereplaceDummyDer,(replaceDummyDer2Exp,(stateexpcall,dummyderexp)));
        (seqns1,(_,_)) = BackendEquation.traverseBackendDAEEqnsWithUpdate(seqns,traversereplaceDummyDer,(replaceDummyDer2Exp,(stateexpcall,dummyderexp)));
       then (BackendDAE.EQSYSTEM(v,eqns,m,mt,matching),BackendDAE.SHARED(kv,ev,av,ie1,seqns1,constrs,clsAttrs,cache,env,funcs,BackendDAE.EVENT_INFO(wclst,zeroCrossingLst),eoc,btp,symjacs));

    case (stateexpcall,dummyderexp,BackendDAE.EQSYSTEM(v,eqns,m,mt,matching),shared,(e :: rest))
      equation
        e_1 = e - 1;
        eqn = BackendDAEUtil.equationNth(eqns, e_1);
        (eqn_1,_) = traverseBackendDAEExpsEqn(eqn, replaceDummyDer2Exp,(stateexpcall,dummyderexp));
        (eqn_1,(v_1,_)) = traverseBackendDAEExpsEqn(eqn_1,replaceDummyDerOthersExp,(v,0));
        eqns_1 = BackendEquation.equationSetnth(eqns, e_1, eqn_1)
         "incidence_row(v\'\',eqn\') => row\' &
          Util.list_replaceat(row\',e\',m) => m\' &
          transpose_matrix(m\') => mt\' &" ;
        (syst,shared) = replaceDummyDer(stateexpcall, dummyderexp, BackendDAE.EQSYSTEM(v_1,eqns_1,m,mt,matching),shared, rest);
      then
        (syst,shared);

    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR, {"- BackendDAETransform.replaceDummyDer failed!"});
      then
        fail();

  end matchcontinue;
end replaceDummyDer;

protected function traversereplaceDummyDer
"function traversereplaceDummyDer
  author: Frenkel TUD 2010-11."
  replaceable type Type_a subtypeof Any;
  input tuple<BackendDAE.Equation,tuple<FuncExpType,Type_a>> inTpl;
  output tuple<BackendDAE.Equation,tuple<FuncExpType,Type_a>> outTpl;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inExpTypeA;
    output tuple<DAE.Exp, Type_a> outExpTypeA;
  end FuncExpType;
algorithm
  outTpl :=
  matchcontinue inTpl
    local 
      BackendDAE.Equation e,e1;
      Type_a ext_arg,ext_arg_1;
      FuncExpType func;
    case ((e,(func,ext_arg)))
      equation
         (e1,ext_arg_1) = traverseBackendDAEExpsEqn(e,func,ext_arg);
      then
        ((e1,(func,ext_arg_1)));
    case inTpl then inTpl;
  end matchcontinue;
end traversereplaceDummyDer;

public function traverseBackendDAEExpsEqn
"function: traverseBackendDAEExpsEqn
  author: Frenkel TUD 2010-11
  Traverse all expressions of a list of Equations. It is possible to change the equations
  and the multidim equations and the algorithms."
  replaceable type Type_a subtypeof Any;
  input BackendDAE.Equation inEquation;
  input FuncExpType func;
  input Type_a inTypeA;
  output BackendDAE.Equation outEquation;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inTpl;
    output tuple<DAE.Exp, Type_a> outTpl;
  end FuncExpType;
algorithm
  (outEquation,(_,outTypeA)) := traverseBackendDAEExpsEqnWithSymbolicOperation(inEquation,traverseBackendDAEExpsEqnWithoutSymbolicOperationHelper,(func,inTypeA));
end traverseBackendDAEExpsEqn;

protected function traverseBackendDAEExpsEqnWithoutSymbolicOperationHelper
  replaceable type Type_a subtypeof Any;
  input tuple<DAE.Exp, tuple<list<DAE.SymbolicOperation>,tuple<FuncExpType,Type_a>>> inTpl;
  output tuple<DAE.Exp, tuple<list<DAE.SymbolicOperation>,tuple<FuncExpType,Type_a>>> outTpl;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inTpl;
    output tuple<DAE.Exp, Type_a> outTpl;
  end FuncExpType;
protected
  FuncExpType func;
  Type_a arg;
  list<DAE.SymbolicOperation> ops;
  DAE.Exp exp;
algorithm
  (exp,(ops,(func,arg))) := inTpl;
  ((exp,arg)) := func((exp,arg));
  outTpl := (exp,(ops,(func,arg)));
end traverseBackendDAEExpsEqnWithoutSymbolicOperationHelper;

public function traverseBackendDAEExpsEqnWithSymbolicOperation
"Traverse all expressions of a list of Equations. It is possible to change the equations
  and the multidim equations and the algorithms."
  replaceable type Type_a subtypeof Any;
  input BackendDAE.Equation inEquation;
  input FuncExpType func;
  input Type_a inTypeA;
  output BackendDAE.Equation outEquation;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, tuple<list<DAE.SymbolicOperation>,Type_a>> inTpl;
    output tuple<DAE.Exp, tuple<list<DAE.SymbolicOperation>,Type_a>> outTpl;
  end FuncExpType;
algorithm
  (outEquation,outTypeA) := matchcontinue (inEquation,func,inTypeA)
    local
      DAE.Exp e1_1,e2_1,e1,e2,cond;
      DAE.ComponentRef cr,cr1;
      Integer size;
      list<DAE.Exp> expl;
      BackendDAE.Equation res;
      BackendDAE.WhenEquation elsepartRes;
      BackendDAE.WhenEquation elsepart;
      DAE.ElementSource source;
      list<Integer> dimSize;
      list<DAE.SymbolicOperation> ops;
      list<DAE.Statement> statementLst;
      list<BackendDAE.Equation> eqns;
      list<list<BackendDAE.Equation>> eqnslst;
      Type_a ext_arg_1,ext_arg_2,ext_arg_3;
    case (BackendDAE.EQUATION(exp = e1,scalar = e2,source = source),_,_)
      equation
        ((e1_1,(ops,ext_arg_1))) = func((e1,({},inTypeA)));
        ((e2_1,(ops,ext_arg_2))) = func((e2,(ops,ext_arg_1)));
        source = List.foldr(ops, DAEUtil.addSymbolicTransformation, source);
      then
        (BackendDAE.EQUATION(e1_1,e2_1,source),ext_arg_2);
    /* array equation */
    case (BackendDAE.ARRAY_EQUATION(dimSize=dimSize,left = e1,right = e2,source = source),_,_)
      equation
        ((e1_1,(ops,ext_arg_1))) = func((e1,({},inTypeA)));
        ((e2_1,(ops,ext_arg_2))) = func((e2,(ops,ext_arg_1)));
        source = List.foldr(ops, DAEUtil.addSymbolicTransformation, source);
      then
        (BackendDAE.ARRAY_EQUATION(dimSize,e1_1,e2_1,source),ext_arg_2);        
    case (BackendDAE.SOLVED_EQUATION(componentRef = cr,exp = e2,source=source),_,_)
      equation
        e1 = Expression.crefExp(cr);
        ((DAE.CREF(cr1,_),(ops,ext_arg_1))) = func((e1,({},inTypeA)));
        ((e2_1,(ops,ext_arg_2))) = func((e2,(ops,ext_arg_1)));
        source = List.foldr(ops, DAEUtil.addSymbolicTransformation, source);
      then
        (BackendDAE.SOLVED_EQUATION(cr1,e2_1,source),ext_arg_1);
    case (BackendDAE.RESIDUAL_EQUATION(exp = e1,source=source),_,_)
      equation
        ((e1_1,(ops,ext_arg_1))) = func((e1,({},inTypeA)));
        source = List.foldr(ops, DAEUtil.addSymbolicTransformation, source);
      then
        (BackendDAE.RESIDUAL_EQUATION(e1_1,source),ext_arg_1);
    /* Algorithms */
    case (BackendDAE.ALGORITHM(size = size,alg=DAE.ALGORITHM_STMTS(statementLst = statementLst),source = source),_,_)
      equation
        (statementLst,(ops,ext_arg_1)) = DAEUtil.traverseDAEEquationsStmts(statementLst, func, ({},inTypeA));
        source = List.foldr(ops, DAEUtil.addSymbolicTransformation, source);
      then (BackendDAE.ALGORITHM(size,DAE.ALGORITHM_STMTS(statementLst),source),ext_arg_1); 
    case (BackendDAE.WHEN_EQUATION(size=size,whenEquation =
          BackendDAE.WHEN_EQ(condition=cond,left = cr,right = e1,elsewhenPart=NONE()),source = source),_,_)
      equation
        e2 = Expression.crefExp(cr);
        ((e1_1,(ops,ext_arg_1))) = func((e1,({},inTypeA)));
        ((DAE.CREF(cr1,_),(ops,ext_arg_2))) = func((e2,(ops,ext_arg_1)));
        ((cond,(ops,ext_arg_3))) = func((cond,(ops,ext_arg_2)));
        source = List.foldr(ops, DAEUtil.addSymbolicTransformation, source);
        res = BackendDAE.WHEN_EQUATION(size,BackendDAE.WHEN_EQ(cond,cr1,e1_1,NONE()),source);
     then
        (res,ext_arg_3);

    case (BackendDAE.WHEN_EQUATION(size=size,whenEquation =
          BackendDAE.WHEN_EQ(condition=cond,left = cr,right = e1,elsewhenPart=SOME(elsepart)),source = source),_,_)
      equation
        ((e1_1,(ops,ext_arg_1))) = func((e1,({},inTypeA)));
        ((cond,(ops,ext_arg_2))) = func((cond,(ops,ext_arg_1)));
        source = List.foldr(ops, DAEUtil.addSymbolicTransformation, source);
        (BackendDAE.WHEN_EQUATION(whenEquation=elsepartRes,source=source),ext_arg_3) = traverseBackendDAEExpsEqnWithSymbolicOperation(BackendDAE.WHEN_EQUATION(size,elsepart,source),func,ext_arg_2);
        res = BackendDAE.WHEN_EQUATION(size,BackendDAE.WHEN_EQ(cond,cr,e1_1,SOME(elsepartRes)),source);
      then
        (res,ext_arg_3);
    case (BackendDAE.COMPLEX_EQUATION(size=size,left = e1,right = e2,source = source),_,_)
      equation
        ((e1_1,(ops,ext_arg_1))) = func((e1,({},inTypeA)));
        ((e2_1,(ops,ext_arg_2))) = func((e2,(ops,ext_arg_1)));
        source = List.foldr(ops, DAEUtil.addSymbolicTransformation, source);
      then
        (BackendDAE.COMPLEX_EQUATION(size,e1_1,e2_1,source),ext_arg_2);   
        
    case (BackendDAE.IF_EQUATION(conditions=expl, eqnstrue=eqnslst, eqnsfalse=eqns, source=source),_,_)
      equation
        (expl,(ops,ext_arg_1)) = traverseBackendDAEExpsLstEqnWithSymbolicOperation(expl,func,({},inTypeA),{});
        source = List.foldr(ops, DAEUtil.addSymbolicTransformation, source);
        (eqnslst,ext_arg_1) = traverseBackendDAEExpsEqnLstLstWithSymbolicOperation(eqnslst,func,ext_arg_1,{});
        (eqns,ext_arg_1) = traverseBackendDAEExpsEqnLstWithSymbolicOperation(eqns,func,ext_arg_1,{});
      then
        (BackendDAE.IF_EQUATION(expl,eqnslst,eqns,source),ext_arg_1);                     
    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR, {"- BackendDAETransform.traverseBackendDAEExpsEqnWithSymbolicOperation failed!"});
      then
        fail();
  end matchcontinue;
end traverseBackendDAEExpsEqnWithSymbolicOperation;

protected function traverseBackendDAEExpsLstEqnWithSymbolicOperation
  replaceable type Type_a subtypeof Any;
  input list<DAE.Exp> inExps;
  input FuncExpType func;
  input Type_a inTypeA;
  input list<DAE.Exp> iAcc;
  output list<DAE.Exp> outExps;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inTpl;
    output tuple<DAE.Exp, Type_a> outTpl;
  end FuncExpType;  
algorithm
  (outExps,outTypeA) := match (inExps,func,inTypeA,iAcc)
    local  
      DAE.Exp exp;
      list<DAE.Exp> rest,exps;
      Type_a arg;
    case({},_,_,_) then (listReverse(iAcc),inTypeA);
    case(exp::rest,_,_,_)
      equation
        ((exp,arg)) = func((exp,inTypeA));
        (exps,arg) = traverseBackendDAEExpsLstEqnWithSymbolicOperation(rest,func,arg,exp::iAcc); 
      then
        (exps,arg);
  end match;
end traverseBackendDAEExpsLstEqnWithSymbolicOperation;

protected function traverseBackendDAEExpsEqnLstWithSymbolicOperation
  replaceable type Type_a subtypeof Any;
  input list<BackendDAE.Equation> inEqns;
  input FuncExpType func;
  input Type_a inTypeA;
  input list<BackendDAE.Equation> iAcc;
  output list<BackendDAE.Equation> outEqns;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, tuple<list<DAE.SymbolicOperation>,Type_a>> inTpl;
    output tuple<DAE.Exp, tuple<list<DAE.SymbolicOperation>,Type_a>> outTpl;
  end FuncExpType;  
algorithm
  (outEqns,outTypeA) := match (inEqns,func,inTypeA,iAcc)
    local  
      BackendDAE.Equation eqn;
      list<BackendDAE.Equation> rest,eqns;
      Type_a arg;
    case({},_,_,_) then (listReverse(iAcc),inTypeA);
    case(eqn::rest,_,_,_)
      equation
        (eqn,arg) = traverseBackendDAEExpsEqnWithSymbolicOperation(eqn,func,inTypeA);
        (eqns,arg) = traverseBackendDAEExpsEqnLstWithSymbolicOperation(rest,func,arg,eqn::iAcc); 
      then
        (eqns,arg);
  end match;
end traverseBackendDAEExpsEqnLstWithSymbolicOperation;

protected function traverseBackendDAEExpsEqnLstLstWithSymbolicOperation
  replaceable type Type_a subtypeof Any;
  input list<list<BackendDAE.Equation>> inEqns;
  input FuncExpType func;
  input Type_a inTypeA;
  input list<list<BackendDAE.Equation>> iAcc;
  output list<list<BackendDAE.Equation>> outEqns;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, tuple<list<DAE.SymbolicOperation>,Type_a>> inTpl;
    output tuple<DAE.Exp, tuple<list<DAE.SymbolicOperation>,Type_a>> outTpl;
  end FuncExpType;  
algorithm
  (outEqns,outTypeA) := match (inEqns,func,inTypeA,iAcc)
    local  
      list<BackendDAE.Equation> eqn;
      list<list<BackendDAE.Equation>> rest,eqnslst;
      Type_a arg;
    case({},_,_,_) then (listReverse(iAcc),inTypeA);
    case(eqn::rest,_,_,_)
      equation
        (eqn,arg) = traverseBackendDAEExpsEqnLstWithSymbolicOperation(eqn,func,inTypeA,{});
        (eqnslst,arg) = traverseBackendDAEExpsEqnLstLstWithSymbolicOperation(rest,func,arg,eqn::iAcc); 
      then
        (eqnslst,arg);
  end match;
end traverseBackendDAEExpsEqnLstLstWithSymbolicOperation;

protected function traverseBackendDAEExpsWhenOperator
"function: traverseBackendDAEExpsWhenOperator
  author: Frenkel TUD 2010-11
  Traverse all expressions of a list of Equations. It is possible to change the equations
  and the multidim equations and the algorithms."
  replaceable type Type_a subtypeof Any;
  input list<BackendDAE.WhenOperator> inReinitStmtLst;
  input FuncExpType func;
  input Type_a inTypeA;
  output list<BackendDAE.WhenOperator> outReinitStmtLst;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inTpl;
    output tuple<DAE.Exp, Type_a> outTpl;
  end FuncExpType;
algorithm
  (outReinitStmtLst,outTypeA) := matchcontinue (inReinitStmtLst,func,inTypeA)
    local
      list<BackendDAE.WhenOperator> res,res1;
      BackendDAE.WhenOperator wop;
      DAE.Exp cond,cond1,msg,level;
      DAE.ComponentRef cr;
      DAE.ElementSource source;
      Type_a ext_arg_1,ext_arg_2;

    case ({},func,inTypeA) then ({},inTypeA);

    case (BackendDAE.REINIT(stateVar=cr,value=cond,source=source)::res,func,inTypeA)
      equation
        (res1,ext_arg_1) =  traverseBackendDAEExpsWhenOperator(res,func,inTypeA);
        ((cond1,ext_arg_2)) = func((cond,ext_arg_1));
      then
        (BackendDAE.REINIT(cr,cond1,source)::res1,ext_arg_2);

    case (BackendDAE.ASSERT(condition=cond,message=msg,level=level,source=source)::res,func,inTypeA)
      equation
        (res1,ext_arg_1) =  traverseBackendDAEExpsWhenOperator(res,func,inTypeA);
        ((cond1,ext_arg_2)) = func((cond,ext_arg_1));
      then
        (BackendDAE.ASSERT(cond1,msg,level,source)::res1,ext_arg_2);

    case (wop::res,func,inTypeA)
      equation
        (res1,ext_arg_1) =  traverseBackendDAEExpsWhenOperator(res,func,inTypeA);
      then
        (wop::res1,ext_arg_1);
     case (_,_,_)
      equation
        Error.addMessage(Error.INTERNAL_ERROR, {"- BackendDAETransform.traverseBackendDAEExpsWhenOperator failed!"});
      then
        fail();
  end matchcontinue;
end traverseBackendDAEExpsWhenOperator;

public function traverseBackendDAEExpsWhenClauseLst
"function: traverseBackendDAEExpsWhenClauseLst
  author: Frenkel TUD 2010-11
  Traverse all expressions of a when clause list. It is possible to change the expressions"
  replaceable type Type_a subtypeof Any; 
  input list<BackendDAE.WhenClause> inWhenClauseLst;
  input FuncExpType func;
  input Type_a inTypeA;
  output list<BackendDAE.WhenClause> outWhenClauseLst;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inTpl;
    output tuple<DAE.Exp, Type_a> outTpl;
  end FuncExpType;  
algorithm
  (outWhenClauseLst,outTypeA) := matchcontinue (inWhenClauseLst,func,inTypeA)
    local
      Option<Integer> elsindx;
      list<BackendDAE.WhenOperator> reinitStmtLst,reinitStmtLst1;
      DAE.Exp cond,cond1;
      list<BackendDAE.WhenClause> wclst,wclst1;
      Type_a ext_arg_1,ext_arg_2,ext_arg_3;

    case ({},func,inTypeA) then ({},inTypeA);

    case (BackendDAE.WHEN_CLAUSE(cond,reinitStmtLst,elsindx)::wclst,func,inTypeA)
      equation
        ((cond1,ext_arg_1)) = func((cond,inTypeA));
        (reinitStmtLst1,ext_arg_2) = traverseBackendDAEExpsWhenOperator(reinitStmtLst,func,ext_arg_1);
        (wclst1,ext_arg_3) = traverseBackendDAEExpsWhenClauseLst(wclst,func,ext_arg_2);
      then
        (BackendDAE.WHEN_CLAUSE(cond1,reinitStmtLst1,elsindx)::wclst1,ext_arg_3);
     case (_,_,_)
      equation
        Error.addMessage(Error.INTERNAL_ERROR, {"- BackendDAETransform.traverseBackendDAEExpsWhenClauseLst failed!"});
      then
        fail();
  end matchcontinue;
end traverseBackendDAEExpsWhenClauseLst;

public function traverseBackendDAEExpsEqnList
"function traverseBackendDAEExpsEqnList
  author: Frenkel TUD 2010-11
  Traverse all expressions of a list of Equations. It is possible to change the equations
  and the multidim equations and the algorithms."
  replaceable type Type_a subtypeof Any;
  input list<BackendDAE.Equation> inEquations;
  input FuncExpType func;
  input Type_a inTypeA;
  output list<BackendDAE.Equation> outEquations;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inTpl;
    output tuple<DAE.Exp, Type_a> outTpl;
  end FuncExpType;
algorithm
  (outEquations,outTypeA):=
  match (inEquations,func,inTypeA)
    local
      list<BackendDAE.Equation> eqns1,eqns;
      BackendDAE.Equation e,e1;
      Type_a ext_arg_1,ext_arg_2;
    case ({},_,_) then ({},inTypeA);
    case (e::eqns,_,_)
      equation
         (e1,ext_arg_1) = traverseBackendDAEExpsEqn(e,func,inTypeA);
         (eqns1,ext_arg_2) = traverseBackendDAEExpsEqnList(eqns,func,ext_arg_1);
      then
        (e1::eqns1,ext_arg_2);
  end match;
end traverseBackendDAEExpsEqnList;

public function replaceDummyDer2Exp
"function: replaceDummyDer2Exp
  author: Frenkel TUD 2010-11
  "
  input tuple<DAE.Exp,tuple<DAE.Exp,DAE.Exp>> inTpl;
  output tuple<DAE.Exp,tuple<DAE.Exp,DAE.Exp>> outTpl;
protected
  DAE.Exp e,e_1,e1,e2;
algorithm
  (e,(e1,e2)) := inTpl;
  ((e_1,_)) := Expression.replaceExp(e,e1,e2);
  outTpl := ((e_1,(e1,e2)));
end replaceDummyDer2Exp;

public function replaceDummyDerOthersExp
"function: equationsCrefs
  author: PA
  This function replaces
  1. der(der_s)  with der2_s (Where der_s is a dummy state)
  2. der(der(v)) with der2_v (where v is a state)
  3. der(v)  for alg. var v with der_v
  in the BackendDAE.Equation given as arguments. To do this it needs the Variables
  also passed as argument to the function to e.g. determine if a variable
  is a dummy variable, etc.  "
  input tuple<DAE.Exp,tuple<BackendDAE.Variables,Integer>> inTpl;
  output tuple<DAE.Exp,tuple<BackendDAE.Variables,Integer>> outTpl;
protected
  DAE.Exp e;
  tuple<BackendDAE.Variables,Integer> vars;
algorithm
  (e,vars) := inTpl;
  outTpl := Expression.traverseExp(e,replaceDummyDerOthersExpFinder,vars);
end replaceDummyDerOthersExp;

protected function traverseReplaceAliasVarsBindExp
"function traverseReplaceAliasVarsBindExp
  Helper function to replaceDummyDer.
  Replaces all variable bindings of the alias variables."
 input tuple<BackendDAE.Var, tuple<DAE.Exp,DAE.Exp>> inTpl;
 output tuple<BackendDAE.Var, tuple<DAE.Exp,DAE.Exp>> outTpl;
algorithm
  outTpl := matchcontinue(inTpl)
    local
      Integer i;
      DAE.Exp e,en,e1,e2;
      BackendDAE.Var v;
    case((v,(e1,e2)))
      equation
        e = BackendVariable.varBindExp(v);
        ((en,i)) = Expression.replaceExp(e,e1,e2);
        true = intGt(i,0);
        v = BackendVariable.setBindExp(v,en);
        v = BackendVariable.mergeVariableOperations(v,{DAE.SUBSTITUTION({en},e)});
      then ((v,(e1,e2)));
    case inTpl then inTpl;
  end matchcontinue;
end traverseReplaceAliasVarsBindExp;

protected function replaceDummyDerOthersExpFinder
"function: replaceDummyDerOthersExpFinder
  author: PA
  Helper function for replaceDummyDerOthersExp"
  input tuple<DAE.Exp,tuple<BackendDAE.Variables,Integer>> inExp;
  output tuple<DAE.Exp,tuple<BackendDAE.Variables,Integer>> outExp;
algorithm
  (outExp) := matchcontinue (inExp)
    local
      DAE.Exp e;
      BackendDAE.Variables vars,vars_1;
      DAE.VarDirection a;
      DAE.VarParallelism prl;
      BackendDAE.Type b;
      Option<DAE.Exp> c;
      Option<Values.Value> d;
      DAE.ComponentRef dummyder,cr;
      DAE.ElementSource source;
      Option<DAE.VariableAttributes> dae_var_attr;
      Option<SCode.Comment> comment;
      DAE.ConnectorType ct;
      list<DAE.Subscript> lstSubs;
      Integer i;

    case ((DAE.CALL(path = Absyn.IDENT(name = "der"),expLst = {DAE.CALL(path = Absyn.IDENT(name = "der"),expLst = {DAE.CREF(componentRef = cr)})}),(vars,i)))
      equation
        ((BackendDAE.VAR(_,BackendDAE.STATE(),a,prl,b,c,d,lstSubs,source,dae_var_attr,comment,ct) :: _),_) = BackendVariable.getVar(cr, vars) "der(der(s)) s is state => der_der_s" ;
        dummyder = ComponentReference.crefPrefixDer(cr);
        dummyder = ComponentReference.crefPrefixDer(dummyder);
        vars_1 = BackendVariable.addVar(BackendDAE.VAR(dummyder, BackendDAE.DUMMY_DER(), a, prl, b, NONE(), NONE(), lstSubs, source, NONE(), comment, ct), vars);
        e = Expression.makeCrefExp(dummyder,DAE.T_REAL_DEFAULT);
      then
        ((e, (vars_1,i+1)));

    case ((DAE.CALL(path = Absyn.IDENT(name = "der"),expLst = {DAE.CREF(componentRef = cr)}),(vars,i)))
      equation
        ((BackendDAE.VAR(_,BackendDAE.DUMMY_DER(),a,prl,b,c,d,lstSubs,source,dae_var_attr,comment,ct) :: _),_) = BackendVariable.getVar(cr, vars) "der(der_s)) der_s is dummy var => der_der_s" ;
        dummyder = ComponentReference.crefPrefixDer(cr);
        vars_1 = BackendVariable.addVar(BackendDAE.VAR(dummyder, BackendDAE.DUMMY_DER(), a, prl, b, NONE(), NONE(), lstSubs, source, NONE(), comment, ct), vars);
        e = Expression.makeCrefExp(dummyder,DAE.T_REAL_DEFAULT);
      then
        ((e, (vars_1,i+1)));

    case ((DAE.CALL(path = Absyn.IDENT(name = "der"),expLst = {DAE.CREF(componentRef = cr)}),(vars,i)))
      equation
        ((BackendDAE.VAR(_,BackendDAE.VARIABLE(),a,prl,b,c,d,lstSubs,source,dae_var_attr,comment,ct) :: _),_) = BackendVariable.getVar(cr, vars) "der(v) v is alg var => der_v" ;
        dummyder = ComponentReference.crefPrefixDer(cr);
        vars_1 = BackendVariable.addVar(BackendDAE.VAR(dummyder, BackendDAE.DUMMY_DER(), a, prl, b, NONE(), NONE(), lstSubs, source, NONE(), comment, ct), vars);
        e = Expression.makeCrefExp(dummyder,DAE.T_REAL_DEFAULT);
      then
        ((e, (vars_1,i+1)));

    case inExp then inExp;

  end matchcontinue;
end replaceDummyDerOthersExpFinder;

public function newDummyVar
"function: newDummyVar
  author: PA
  This function creates a new variable named
  der+<varname> and adds it to the dae."
  input DAE.ComponentRef inComponentRef;
  input BackendDAE.EqSystem syst;
  input DAE.SymbolicOperation op;
  output DAE.ComponentRef outComponentRef;
  output BackendDAE.EqSystem osyst;
algorithm
  (outComponentRef,osyst) := matchcontinue (inComponentRef,syst,op)
    local
      BackendDAE.VarKind kind;
      DAE.VarDirection dir;
      DAE.VarParallelism prl;
      BackendDAE.Type tp;
      Option<DAE.Exp> bind;
      Option<Values.Value> value;
      list<DAE.Subscript> dim;
      DAE.ComponentRef name,dummyvar_cr,var;
      DAE.ElementSource source;
      Option<DAE.VariableAttributes> dae_var_attr;
      Option<SCode.Comment> comment;
      DAE.ConnectorType ct;
      BackendDAE.Variables vars_1,vars;
      BackendDAE.EquationArray eqns;
      BackendDAE.Var dummyvar;
      Option<BackendDAE.IncidenceMatrix> om,omT;
      BackendDAE.Matching matching;

    case (var,BackendDAE.EQSYSTEM(vars,eqns,om,omT,matching),op)
      equation
        ((BackendDAE.VAR(name,kind,dir,prl,tp,bind,value,dim,source,dae_var_attr,comment,ct) :: _),_) = BackendVariable.getVar(var, vars);
        dummyvar_cr = ComponentReference.crefPrefixDer(name);
        /* start value is not the same */
        source = DAEUtil.addSymbolicTransformation(source,op);
        dummyvar = BackendDAE.VAR(dummyvar_cr,BackendDAE.DUMMY_DER(),dir,prl,tp,NONE(),NONE(),dim,source,NONE(),comment,ct);
        /* Dummy variables are algebraic variables, hence fixed = false */
        dummyvar = BackendVariable.setVarFixed(dummyvar,false);
        vars_1 = BackendVariable.addNewVar(dummyvar, vars);
      then
        (dummyvar_cr,BackendDAE.EQSYSTEM(vars_1,eqns,om,omT,matching));

    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR, {"BackendDAE.newDummyVar failed!"});
      then
        fail();
  end matchcontinue;
end newDummyVar;

protected function selectDummyState
"function: selectDummyState
  author: PA
  This function is the heuristic to select among the states which one
  will be transformed into  an algebraic variable, a so called dummy state
 (dummy derivative). It should in the future consider initial values, etc.
  inputs:  (DAE.ComponentRef list, /* variable names */
            int list, /* variable numbers */
            BackendDAE,
            IncidenceMatrix,
            IncidenceMatrixT)
  outputs: (DAE.ComponentRef, int)"
  input list<DAE.ComponentRef> varCrefs;
  input list<Integer> varIndices;
  input BackendDAE.EqSystem syst;
  input array<Integer> mapIncRowEqn;
  input BackendDAE.StateOrder so;
  output DAE.ComponentRef outComponentRef;
  output Integer outInteger;
algorithm
  (outComponentRef,outInteger):=
  matchcontinue (varCrefs,varIndices,syst,mapIncRowEqn,so)
    local
      DAE.ComponentRef s;
      Integer sn;
      BackendDAE.Variables vars;
      BackendDAE.IncidenceMatrix m;
      BackendDAE.IncidenceMatrixT mt;
      BackendDAE.EquationArray eqns;
      list<tuple<DAE.ComponentRef,Integer,Real>> prioTuples;

    case (varCrefs,varIndices,BackendDAE.EQSYSTEM(orderedVars=vars,orderedEqs = eqns,m=SOME(m),mT=SOME(mt)),_,_)
      equation
        prioTuples = calculateVarPriorities(varCrefs,varIndices,vars,eqns,m,mt,mapIncRowEqn,so,{});
        //print("priorities:");print(stringDelimitList(List.map(prioTuples,printPrioTuplesStr),","));print("\n");
        (s,sn) = selectMinPrio(prioTuples);
      then (s,sn);

    case ({},_,syst,_,_)
      equation
        Error.addMessage(Error.INTERNAL_ERROR, {"BackendDAETransform.selectDummyState: no state to select"});
        BackendDump.dumpEqSystem(syst);
      then
        fail();

  end matchcontinue;
end selectDummyState;

protected function selectMinPrio
"Selects the state with lowest priority. This will become a dummy state"
  input list<tuple<DAE.ComponentRef,Integer,Real>> tuples;
  output DAE.ComponentRef s;
  output Integer sn;
algorithm
  (s,sn) := match(tuples)
    case(tuples)
      equation
        ((s,sn,_)) = List.reduce(tuples,ssPrioTupleMin);
      then (s,sn);
  end match;
end selectMinPrio;

protected function ssPrioTupleMin
"Select the minimum tuple of two tuples"
  input tuple<DAE.ComponentRef,Integer,Real> tuple1;
  input tuple<DAE.ComponentRef,Integer,Real> tuple2;
  output tuple<DAE.ComponentRef,Integer,Real> tuple3;
algorithm
  tuple3 := matchcontinue(tuple1,tuple2)
    local DAE.ComponentRef cr1,cr2;
      Integer ns1,ns2;
      Real rs1,rs2;
    case((cr1,ns1,rs1),(cr2,ns2,rs2))
      equation
        true = (rs1 <. rs2);
      then ((cr1,ns1,rs1));

    case ((cr1,ns1,rs1),(cr2,ns2,rs2))
      equation
        true = (rs2 <. rs1);
      then ((cr2,ns2,rs2));

    //exactly equal, choose first one.
    case ((cr1,ns1,rs1),(cr2,ns2,rs2)) then ((cr1,ns1,rs1));

  end matchcontinue;
end ssPrioTupleMin;

protected function calculateVarPriorities
"Calculates state selection priorities"
  input list<DAE.ComponentRef> inVarCrefs;
  input list<Integer> inVarIndices;
  input BackendDAE.Variables vars;
  input BackendDAE.EquationArray eqns;
  input BackendDAE.IncidenceMatrix m;
  input BackendDAE.IncidenceMatrixT mt;
  input array<Integer> mapIncRowEqn;
  input BackendDAE.StateOrder so;
  input list<tuple<DAE.ComponentRef,Integer,Real>> iTuples;
  output list<tuple<DAE.ComponentRef,Integer,Real>> tuples;
algorithm
  tuples := match(inVarCrefs,inVarIndices,vars,eqns,m,mt,mapIncRowEqn,so,iTuples)
    local 
      DAE.ComponentRef varCref;
      Integer varIndx;
      BackendDAE.Var v;
      Real prio,prio1,prio2;
      list<DAE.ComponentRef> varCrefs;
      list<Integer> varIndices;    
    
    case ({},{},_,_,_,_,_,_,_) then listReverse(iTuples);
    case (varCref::varCrefs,varIndx::varIndices,_,_,_,_,_,_,_)
      equation
        v = BackendVariable.getVarAt(vars,varIndx);
        prio1 = varStateSelectPrio(v);
        prio2 = varStateSelectHeuristicPrio(v,varIndx,vars,eqns,m,mt,mapIncRowEqn,so);
        prio = prio1 +. prio2;
        Debug.fcall(Flags.DUMMY_SELECT,BackendDump.debugStrCrefStrRealStrRealStrRealStr,("Calc Prio for ",varCref,"\n Prio StateSelect : ",prio1,"\n Prio Heuristik : ",prio2,"\n ### Prio Result : ",prio,"\n"));
      then
        calculateVarPriorities(varCrefs,varIndices,vars,eqns,m,mt,mapIncRowEqn,so,(varCref,varIndx,prio)::iTuples);
  end match;
end calculateVarPriorities;

protected function varStateSelectHeuristicPrio
"function varStateSelectHeuristicPrio
  author: PA
  A heuristic for selecting states when no stateSelect information is available.
  This heuristic is based on.
  1. If a state variable s has an equation on the form s = expr(s1,s2,...,sn) where s1..sn are states
     it should be a candiate for dummy state. Like for instance phi_rel = J1.phi-J2.phi will make phi_rel
     a candidate for dummy state whereas J1.phi and J2.phi would be candidates for states.

  2. If a state variable komponent_x.s has been selected as a dummy state then komponent_x.s2 could also
     be a dummy_state. Rationale: This will increase probability that all states belong to the same component
     which is more likely what a user expects.

  3. A priority based on the number of selectable states with the same name.
     For example if the state candidates are: m1.s, m1.v, m2.s, m2.v sd.s_rel (Two translational masses and a springdamper)
     then sd.s_rel should have lower priority than the others."
  input BackendDAE.Var v;
  input Integer vindx;
  input BackendDAE.Variables vars;
  input BackendDAE.EquationArray eqns;
  input BackendDAE.IncidenceMatrix m;
  input BackendDAE.IncidenceMatrixT mt;
  input array<Integer> mapIncRowEqn;
  input BackendDAE.StateOrder so;
  output Real prio;
protected
  list<Integer> vEqns;
  DAE.ComponentRef vCr;
//  Integer vindx;
  Real prio1,prio2,prio3,prio4,prio5,prio6,prio7;
algorithm
//  (_,vindx::_) := BackendVariable.getVar(BackendVariable.varCref(v),vars); // Variable index not stored in var itself => lookup required
  vEqns := BackendDAEUtil.eqnsForVarWithStates(mt,vindx);
  vEqns := List.map1r(vEqns,arrayGet,mapIncRowEqn);
  vEqns := List.unique(vEqns);  
  vCr := BackendVariable.varCref(v);
  prio1 := varStateSelectHeuristicPrio1(vCr,vEqns,vars,eqns);
  prio2 := varStateSelectHeuristicPrio2(vCr,vars);
  prio3 := varStateSelectHeuristicPrio3(vCr,vars);
//  prio4 := varStateSelectHeuristicPrio4(v);
  prio5 := varStateSelectHeuristicPrio5(v);
  prio6 := varStateSelectHeuristicPrio6(v);
  prio7 := varStateSelectHeuristicPrio7(v,so,vars);
  prio:= prio1 +. prio2 +. prio3 +. prio5 +. prio6 +. prio7;// +. prio4;
  dumpvarStateSelectHeuristicPrio(prio1,prio2,prio3,prio5,prio6,prio7);
end varStateSelectHeuristicPrio;

protected function dumpvarStateSelectHeuristicPrio
  input Real Prio1;
  input Real Prio2;
  input Real Prio3;
//  input Real Prio4;
  input Real Prio5;
  input Real Prio6;
  input Real Prio7;
algorithm
  _ := matchcontinue(Prio1,Prio2,Prio3,Prio5,Prio6,Prio7)
    case(_,_,_,_,_,_)
      equation
        true = Flags.isSet(Flags.DUMMY_SELECT);
        print("Prio 1 : " +& realString(Prio1) +& "\n");
        print("Prio 2 : " +& realString(Prio2) +& "\n");
        print("Prio 3 : " +& realString(Prio3) +& "\n");
//        print("Prio 4 : " +& realString(Prio4) +& "\n");
        print("Prio 5 : " +& realString(Prio5) +& "\n");
        print("Prio 6 : " +& realString(Prio6) +& "\n");
        print("Prio 7 : " +& realString(Prio7) +& "\n");
      then
        ();
    else then ();        
  end matchcontinue;
end dumpvarStateSelectHeuristicPrio;

protected function varStateSelectHeuristicPrio7
"function varStateSelectHeuristicPrio6
  author: Frenkel TUD 2012-08
  Helper function to varStateSelectHeuristicPrio.
  added prio for states/variables wich are derivatives of deselected states"
  input BackendDAE.Var v;
  input BackendDAE.StateOrder so;
  input BackendDAE.Variables vars;
  output Real prio;
algorithm
  prio := matchcontinue(v,so,vars)
    local DAE.ComponentRef cr,pcr;
    case(BackendDAE.VAR(varName=cr),_,_)
      equation
        pcr::_ = getDerStateOrder(cr, so);
        (BackendDAE.VAR(varKind=BackendDAE.DUMMY_STATE())::{},_) = BackendVariable.getVar(pcr, vars);
      then -1.0;
    else then 0.0;
  end matchcontinue;
end varStateSelectHeuristicPrio7;

protected function varStateSelectHeuristicPrio6
"function varStateSelectHeuristicPrio6
  author: Frenkel TUD 2012-04
  Helper function to varStateSelectHeuristicPrio.
  added prio for variables with $_DER. name. Thouse are dummy_states
  added by index reduction from normal variables"
  input BackendDAE.Var v;
  output Real prio;
algorithm
  prio := matchcontinue(v)
    local DAE.ComponentRef cr,pcr;
    case(BackendDAE.VAR(varName=cr))
      equation
        pcr = ComponentReference.crefFirstCref(cr);
        true = ComponentReference.crefEqual(pcr,ComponentReference.makeCrefIdent("$_DER",DAE.T_REAL_DEFAULT,{}));
      then -100.0;
    else then 0.0;
  end matchcontinue;
end varStateSelectHeuristicPrio6;

protected function varStateSelectHeuristicPrio5
"function varStateSelectHeuristicPrio5
  author: Frenkel TUD 2011-05
  Helper function to varStateSelectHeuristicPrio.
  added prio for variables with fixed = true "
  input BackendDAE.Var v;
  output Real prio;
algorithm
  prio := matchcontinue(v)
    case(v)
      equation
        true = BackendVariable.varFixed(v);
      then 1.0;
    else then 0.0;
  end matchcontinue;
end varStateSelectHeuristicPrio5;

protected function varStateSelectHeuristicPrio4
"function varStateSelectHeuristicPrio4
  author: wbraun
  Helper function to varStateSelectHeuristicPrio.
  added prio for variables with a start value "
  input BackendDAE.Var v;
  output Real prio;
algorithm
  prio := matchcontinue(v)
    local 
      DAE.Exp e;
    case(v)
      equation
        e = BackendVariable.varStartValueFail(v);
        true = Expression.isZero(e);
      then -0.1;
    else then 0.0;
  end matchcontinue;
end varStateSelectHeuristicPrio4;


protected function varStateSelectHeuristicPrio3
"function varStateSelectHeuristicPrio3
  author: PA
  Helper function to varStateSelectHeuristicPrio"
  input DAE.ComponentRef cr;
  input BackendDAE.Variables vars;
  output Real prio;
algorithm
  prio := match(cr,vars)
    local Integer i; Real c;
    case(cr,vars)
      equation
        ((_,i)) = BackendVariable.traverseBackendDAEVars(vars,varHasSameLastIdent,(cr,0));
        c = intReal(i);
        prio = c *. 0.01;
      then prio;
  end match;
end varStateSelectHeuristicPrio3;

protected function varHasSameLastIdent
"function varHasSameLastIdent
  Helper funciton to varStateSelectHeuristicPrio3.
  Returns true if the variable has the same name (the last identifier)
  as the variable name given as second argument."
 input tuple<BackendDAE.Var, tuple<DAE.ComponentRef,Integer>> inTpl;
 output tuple<BackendDAE.Var, tuple<DAE.ComponentRef,Integer>> outTpl;
algorithm
  outTpl := matchcontinue(inTpl)
    local 
      DAE.ComponentRef cr,cr2;
      BackendDAE.Var v;
      Integer i;
    case((v,(cr,i)))
      equation
        cr2 = BackendVariable.varCref(v);
        true = ComponentReference.crefLastIdentEqual(cr,cr2);
      then ((v,(cr,i+1)));
    else then inTpl;
  end matchcontinue;
end varHasSameLastIdent;

protected function varStateSelectHeuristicPrio2
"function varStateSelectHeuristicPrio2
  author: PA
  Helper function to varStateSelectHeuristicPrio"
  input DAE.ComponentRef cr;
  input BackendDAE.Variables vars;
  output Real prio;
algorithm
  prio := matchcontinue(cr,vars)
    local
    case(cr,vars)
      equation
        ((_,true)) = BackendVariable.traverseBackendDAEVars(vars,varInSameComponent,(cr,false));
      then -1.0;
    case(cr,vars) then 0.0;
  end matchcontinue;
end varStateSelectHeuristicPrio2;

protected function varInSameComponent
"function varInSameComponent
  Helper funciton to varStateSelectHeuristicPrio2.
  Returns true if the variable is defined in the same sub
  component as the variable name given as second argument."
 input tuple<BackendDAE.Var, tuple<DAE.ComponentRef,Boolean>> inTpl;
 output tuple<BackendDAE.Var, tuple<DAE.ComponentRef,Boolean>> outTpl;
algorithm
  outTpl := matchcontinue(inTpl)
    local 
      DAE.ComponentRef cr,cr2;
      BackendDAE.Var v;
    case((v,(cr,true))) then ((v,(cr,true)));
    case((v,(cr,_)))
      equation
        cr2 = BackendVariable.varCref(v);
        true = BackendVariable.isDummyStateVar(v);
        true = ComponentReference.crefEqualNoStringCompare(ComponentReference.crefStripLastIdent(cr2),ComponentReference.crefStripLastIdent(cr));
      then ((v,(cr,true)));
    else then inTpl;
  end matchcontinue;
end varInSameComponent;

protected function varStateSelectHeuristicPrio1
"function varStateSelectHeuristicPrio1
  author:  PA
  Helper function to varStateSelectHeuristicPrio"
  input DAE.ComponentRef cr;
  input list<Integer> inEqnLst;
  input BackendDAE.Variables vars;
  input BackendDAE.EquationArray eqns;
  output Real prio;
algorithm
  prio := matchcontinue(cr,inEqnLst,vars,eqns)
    local 
      Integer e; BackendDAE.Equation eqn;
      list<Integer> eqnLst;
      DAE.ComponentRef dcr;
      
    case(_,{},_,_) then 0.0;
    case(_,e::eqnLst,vars,eqns)
      equation
        eqn = BackendDAEUtil.equationNth(eqns,e-1);
        true = isStateConstraintEquation(cr,eqn,vars);
      then -1.0;
    case(_,e::eqnLst,_,_)
      equation
        eqn = BackendDAEUtil.equationNth(eqns,e-1);
        (_,dcr,_,_,_) = BackendEquation.derivativeEquation(eqn);
        false = ComponentReference.crefEqualNoStringCompare(cr,dcr);
        true = BackendVariable.isState(dcr,vars);
      then +0.5;
    case(_,e::eqnLst,_,_)
      equation
        eqn = BackendDAEUtil.equationNth(eqns,e-1);
        true = isStateAssignEquation(cr,eqn);
      then -0.05;
    case(_,_::eqnLst,_,_) then varStateSelectHeuristicPrio1(cr,eqnLst,vars,eqns);
 end matchcontinue;
end varStateSelectHeuristicPrio1;

protected function isStateConstraintEquation
"function isStateConstraintEquation
  author: PA
  Help function to varStateSelectHeuristicPrio1
  Returns true if an equation is on the form cr = expr(s1,s2...sn) for states cr, s1,s2..,sn"
  input DAE.ComponentRef cr;
  input BackendDAE.Equation eqn;
  input BackendDAE.Variables vars;
  output Boolean res;
algorithm
  res := matchcontinue(cr,eqn,vars)
    local
      DAE.ComponentRef cr2;
      list<DAE.ComponentRef> crs;
      list<list<BackendDAE.Var>> crVars;
      DAE.Exp e2;

    // s = expr(s1,..,sn)  where s1 .. sn are states
    case(cr,BackendDAE.EQUATION(exp = DAE.CREF(cr2,_), scalar = e2),vars)
      equation
        true = ComponentReference.crefEqualNoStringCompare(cr,cr2);
        _::_::_ = Expression.terms(e2);
        crs = Expression.extractCrefsFromExp(e2);
        (crVars,_) = List.map1_2(crs,BackendVariable.getVar,vars);
        // fails if not all mapped calls return true
      then List.mapAllValueBool(List.flatten(crVars),BackendVariable.isStateVar,true);

    case(cr,BackendDAE.EQUATION(exp = e2, scalar = DAE.CREF(cr2,_)),vars)
      equation
        true = ComponentReference.crefEqualNoStringCompare(cr,cr2);
        _::_::_ = Expression.terms(e2);
        crs = Expression.extractCrefsFromExp(e2);
        (crVars,_) = List.map1_2(crs,BackendVariable.getVar,vars);
        // fails if not all mapped calls return true
      then List.mapAllValueBool(List.flatten(crVars),BackendVariable.isStateVar,true);

    else false;
  end matchcontinue;
end isStateConstraintEquation;

protected function isStateAssignEquation
"function isStateAssignEquation
  author: Frenkel TUD 2011-04
  Help function to varStateSelectHeuristicPrio1
  Returns true if an equation is on the form cr = expr(s1,s2...sn,pv1,...,pvn) for states cr, s1,s2..,sn, and parameters pv1,...,pvn "
  input DAE.ComponentRef cr;
  input BackendDAE.Equation eqn;
  output Boolean res;
algorithm
  res := matchcontinue(cr,eqn)
    local
      DAE.ComponentRef cr2;
      DAE.Exp e2;

    case(cr,BackendDAE.EQUATION(exp = DAE.CREF(cr2,_), scalar = e2))
      equation
        true = ComponentReference.crefEqualNoStringCompare(cr,cr2);
        false = Expression.expHasCref(e2, cr);
        //_::_::_ = Expression.terms(e2);
      then true;

    case(cr,BackendDAE.EQUATION(exp = e2, scalar = DAE.CREF(cr2,_)))
      equation
        true = ComponentReference.crefEqualNoStringCompare(cr,cr2);
        false = Expression.expHasCref(e2, cr);
        //_::_::_ = Expression.terms(e2);
      then true;

    else false;
  end matchcontinue;
end isStateAssignEquation;

protected function varStateSelectPrio
"function varStateSelectPrio
  Helper function to calculateVarPriorities.
  Calculates a priority contribution bases on the stateSelect attribute."
  input BackendDAE.Var v;
  output Real prio;
  protected
  DAE.StateSelect ss;
algorithm
  ss := BackendVariable.varStateSelect(v);
  prio := varStateSelectPrio2(ss);
end varStateSelectPrio;

protected function varStateSelectPrio2
"helper function to varStateSelectPrio"
  input DAE.StateSelect ss;
  output Real prio;
algorithm
  prio := match(ss)
    case (DAE.NEVER()) then -10.0;
    case (DAE.AVOID()) then 0.0;
    case (DAE.DEFAULT()) then 10.0;
    case (DAE.PREFER()) then 50.0;
    case (DAE.ALWAYS()) then 100.0;
  end match;
end varStateSelectPrio2;

protected function calculateDummyStatePriorities
"function: calculateDummyStatePriority
  Calculates a priority for dummy state candidates.
  The state with lowest priority number is selected as a dummy variable.
  Heuristic parameters:
   1. States that has an initial condition is given pentalty 10.
   2. BackendDAE.Equation s1= p  s2 with states s1 and s2 gives penalty 1 for state s1.
  The heuristic parameters are summed to get the priority number."
  input list<DAE.ComponentRef> inExpComponentRefLst;
  input list<Integer> inIntegerLst;
  input BackendDAE.BackendDAE inBackendDAE;
  input BackendDAE.IncidenceMatrix inIncidenceMatrix;
  input BackendDAE.IncidenceMatrixT inIncidenceMatrixT;
  output list<tuple<DAE.ComponentRef, Integer, Integer>> outTplExpComponentRefIntegerIntegerLst;
algorithm
  outTplExpComponentRefIntegerIntegerLst:=
  matchcontinue (inExpComponentRefLst,inIntegerLst,inBackendDAE,inIncidenceMatrix,inIncidenceMatrixT)
    local
      DAE.ComponentRef cr;
      Integer indx,prio;
      list<tuple<DAE.ComponentRef, Integer, Integer>> res;
      list<DAE.ComponentRef> crs;
      list<Integer> indxs;
      BackendDAE.BackendDAE dae;
      array<list<Integer>> m,mt;
    case ({},{},_,_,_) then {};
    case ((cr :: crs),(indx :: indxs),dae,m,mt)
      equation
        (cr,indx,prio) = calculateDummyStatePriority(cr, indx, dae, m, mt);
        res = calculateDummyStatePriorities(crs, indxs, dae, m, mt);
      then
        ((cr,indx,prio) :: res);
  end matchcontinue;
end calculateDummyStatePriorities;

protected function calculateDummyStatePriority
  input DAE.ComponentRef inComponentRef;
  input Integer inInteger;
  input BackendDAE.BackendDAE inBackendDAE;
  input BackendDAE.IncidenceMatrix inIncidenceMatrix;
  input BackendDAE.IncidenceMatrixT inIncidenceMatrixT;
  output DAE.ComponentRef outComponentRef1;
  output Integer outInteger2;
  output Integer outInteger3;
algorithm
  (outComponentRef1,outInteger2,outInteger3):=
  matchcontinue (inComponentRef,inInteger,inBackendDAE,inIncidenceMatrix,inIncidenceMatrixT)
    local
      DAE.ComponentRef cr;
      Integer indx;
      BackendDAE.BackendDAE dae;
      array<list<Integer>> m,mt;
    case (cr,indx,dae,m,mt) then (cr,indx,0);
  end matchcontinue;
end calculateDummyStatePriority;

protected function statesInEqns
"function: statesInEqns
  author: PA
  Helper function to reduce_index_dummy_der.
  Returns all states in the equations given as equation index list.
  inputs:  (int list /* eqns */,
              BackendDAE,
              IncidenceMatrix,
              IncidenceMatrixT)
  outputs: (DAE.ComponentRef list, /* name for each state */
              int list)  /* number for each state */"
  input list<Integer> inIntegerLst;
  input BackendDAE.EqSystem syst;
  input list<DAE.ComponentRef> inExpComponentRefLst;
  input list<Integer> inIntegerLst1;
  output list<DAE.ComponentRef> outExpComponentRefLst;
  output list<Integer> outIntegerLst;
algorithm
  (outExpComponentRefLst,outIntegerLst):=
  matchcontinue (inIntegerLst,syst,inExpComponentRefLst,inIntegerLst1)
    local
      list<DAE.ComponentRef> res1,res11;
      list<Integer> res2,res22,rest;
      Integer e;
      BackendDAE.Variables vars;
      BackendDAE.EquationArray eqns;
      array<list<Integer>> m;
      String se;
      Integer e_1;
      DAE.ElementSource source;
      
    case ({},_,_,_) then (inExpComponentRefLst,inIntegerLst1);
    case ((e :: rest),syst as BackendDAE.EQSYSTEM(orderedVars = vars,m=SOME(m)),_,_)
      equation
        (res11,res22) = statesInVars(vars, m[e],inExpComponentRefLst,inIntegerLst1);
        (res1,res2) = statesInEqns(rest, syst, res11, res22);
      then
        (res1,res2);
    case ((e :: rest),BackendDAE.EQSYSTEM(orderedEqs = eqns),_,_)
      equation
        se = intString(e);
        se = stringAppendList({"-BackendDAETransform.statesInEqns failed for eqn: ",se,"\n"});
        e_1 = e - 1;
        source = BackendEquation.equationSource(BackendDAEUtil.equationNth(eqns,e_1));
        Error.addSourceMessage(Error.INTERNAL_ERROR, {se}, DAEUtil.getElementSourceFileInfo(source));        
      then
        fail();
  end matchcontinue;
end statesInEqns;

protected function statesInVars "function: statesInVars
  author: PA

  Helper function to states_in_eqns

  inputs:  (Var list, int list)
  outputs: (DAE.ComponentRef list, /* names of the states */
              int list /* number for each state */)
"
  input BackendDAE.Variables vars;
  input list<Integer> inIntegerLst;
  input list<DAE.ComponentRef> inExpComponentRefLst;
  input list<Integer> inIntegerLst1;  
  output list<DAE.ComponentRef> outExpComponentRefLst;
  output list<Integer> outIntegerLst;
algorithm
  (outExpComponentRefLst,outIntegerLst):=
  matchcontinue (vars,inIntegerLst,inExpComponentRefLst,inIntegerLst1)
    local
      Integer v,v_1;
      DAE.ComponentRef cr;
      list<DAE.ComponentRef> res1;
      list<Integer> res2,rest;
    case (vars,{},_,_) then (inExpComponentRefLst,inIntegerLst1);
    case (vars,(v :: rest),_,_)
      equation
        false = intGt(v,0);
        v_1 = intAbs(v);
        false = listMember(v_1,inIntegerLst1);
        BackendDAE.VAR(varName = cr) = BackendVariable.getVarAt(vars,v_1);
        (res1,res2) = statesInVars(vars, rest,cr :: inExpComponentRefLst,v_1 :: inIntegerLst1);
      then
        (res1,res2);
    case (vars,(v :: rest),_,_)
      equation
        (res1,res2) = statesInVars(vars, rest,inExpComponentRefLst,inIntegerLst1);
      then
        (res1,res2);
  end matchcontinue;
end statesInVars;

protected function differentiateEqns
"function: differentiateEqns
  author: PA
  This function takes a dae, its incidence matrices and the number of
  equations an variables and a list of equation indices to
  differentiate. This is used in the index reduction algorithm
  using dummy derivatives, when all marked equations are differentiated.
  The function updates the dae, the incidence matrix and returns
  a list of indices of the differentiated equations, they are added last in
  the dae.
  inputs:  (BackendDAE,
            IncidenceMatrix,
            IncidenceMatrixT,
            int, /* number of vars */
            int, /* number of eqns */
            int list) /* equations */
  outputs: (BackendDAE,
            IncidenceMatrix,
            IncidenceMatrixT,
            int, /* number of vars */
            int, /* number of eqns */
            int list /* differentiated equations */)"
  input BackendDAE.EqSystem isyst;
  input BackendDAE.Shared ishared;
  input list<Integer> inIntegerLst6;
  input BackendDAE.StateOrder inStateOrd;
  input BackendDAE.ConstraintEquations inOrgEqnsLst;  
  output BackendDAE.EqSystem osyst;
  output BackendDAE.Shared oshared;
  output list<Integer> outIntegerLst6;
  output BackendDAE.StateOrder outStateOrd;
  output BackendDAE.ConstraintEquations outOrgEqnsLst;  
algorithm
  (osyst,oshared,outIntegerLst6,outStateOrd,outOrgEqnsLst):=
  matchcontinue (isyst,ishared,inIntegerLst6,inStateOrd,inOrgEqnsLst)
    local
      array<list<Integer>> m,mt;
      Integer e_1,leneqns,e;
      BackendDAE.Equation eqn,eqn_1;
      BackendDAE.EquationArray eqns_1,eqns;
      list<Integer> reqns,es;
      BackendDAE.Variables v;
      list<BackendDAE.Var> ev;
      BackendDAE.Matching matching;
      BackendDAE.EqSystem syst;
      BackendDAE.Shared shared;
      BackendDAE.StateOrder so;
      BackendDAE.ConstraintEquations orgEqnsLst;  

    case (syst,shared,{},_,_) then (syst,shared,{},inStateOrd,inOrgEqnsLst);

    case (BackendDAE.EQSYSTEM(v,eqns,SOME(m),SOME(mt),matching),shared,(e :: es),_,_)
      equation
        e_1 = e - 1;
        eqn = BackendDAEUtil.equationNth(eqns, e_1);
        ev = BackendEquation.equationsLstVarsWithoutRelations({eqn},v);
        false = BackendVariable.hasContinousVar(ev);
        BackendDAEEXT.markDifferentiated(e) "length gives index of new equation Mark equation as differentiated so it won\'t be differentiated again" ;
        (syst,shared,reqns,so,orgEqnsLst) = differentiateEqns(BackendDAE.EQSYSTEM(v,eqns,SOME(m),SOME(mt),matching),shared, es,inStateOrd,inOrgEqnsLst);
      then
        (syst,shared,(e :: reqns),so,orgEqnsLst);
        
    case (BackendDAE.EQSYSTEM(v,eqns,SOME(m),SOME(mt),matching),shared,(e :: es),_,_)
      equation
        e_1 = e - 1;
        eqn = BackendDAEUtil.equationNth(eqns, e_1);

        eqn_1 = Derive.differentiateEquationTime(eqn, v, shared);
        // print( "differentiated equation " +& intString(e) +& " " +& BackendDump.equationStr(eqn) +& "\n");
        // print( "differentiated equation " +& intString(e) +& " " +& BackendDump.equationStr(eqn_1) +& "\n to \n");
        (eqn_1,so) = traverseBackendDAEExpsEqn(eqn_1, replaceStateOrderExp,inStateOrd);
        // print(BackendDump.equationStr(eqn_1) +& "\n");
        Debug.fcall(Flags.BLT_DUMP, debugdifferentiateEqns,(eqn,eqn_1));
        eqns_1 = BackendEquation.equationAdd(eqn_1,eqns);
        leneqns = BackendDAEUtil.equationArraySize(eqns_1);
        // print("New Equation: " +& intString(leneqns) +& "\n");
        BackendDAEEXT.markDifferentiated(e) "length gives index of new equation Mark equation as differentiated so it won\'t be differentiated again" ;
        (syst,shared,reqns,so,orgEqnsLst) = differentiateEqns(BackendDAE.EQSYSTEM(v,eqns_1,SOME(m),SOME(mt),matching),shared, es,inStateOrd,inOrgEqnsLst);
      then
        (syst,shared,(leneqns :: (e :: reqns)),so,orgEqnsLst);
    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR, {"-BackendDAETranfrom.differentiateEqns failed!"}); 
      then
        fail();
  end matchcontinue;
end differentiateEqns;

protected function debugdifferentiateEqns
  input tuple<BackendDAE.Equation,BackendDAE.Equation> inTpl;
protected
  BackendDAE.Equation a,b;
algorithm
  (a,b) := inTpl;
  print("High index problem, differentiated equation:\n" +& BackendDump.equationStr(a) +& "\nto\n" +& BackendDump.equationStr(b) +& "\n");
end debugdifferentiateEqns;

end BackendDAETransform;
