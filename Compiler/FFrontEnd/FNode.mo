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

encapsulated package FNode
" file:        FNode.mo
  package:     FNode
  description: A node structure to hold Modelica constructs

  RCS: $Id: FNode.mo 14085 2012-11-27 12:12:40Z adrpo $

  This module builds nodes out of SCode 
"

// public imports
public 
import Absyn;
import DAE;
import SCode;
import Util;
import FCore;

// protected imports
protected 
import Error;
import List;
import FGraph;

public
type Name = FCore.Name;
type Id = FCore.Id;
type Seq = FCore.Seq;
type Next = FCore.Next;
type Node = FCore.Node;
type Data = FCore.Data;
type Kind = FCore.Kind;
type Ref = FCore.Ref;
type Refs = FCore.Refs;
type Children = FCore.Children;
type Parents = FCore.Parents;
type Scope = FCore.Scope;
type ImportTable = FCore.ImportTable;
type Graph = FCore.Graph;
type Extra = FCore.Extra;
type Visited = FCore.Visited;
type Import = FCore.Import;
type AvlTree = FCore.CAvlTree;
type AvlKey = FCore.CAvlKey;
type AvlValue = FCore.CAvlValue;
type AvlTreeValue = FCore.CAvlTreeValue;

// these names are used mostly for edges in the graph
// the edges are saved inside the AvlTree ("name", Ref)
constant Name tyNodeName     = "$ty" "type node";
constant Name refNodeName    = "$ref" "reference node";
constant Name modNodeName    = "$mod" "modifier node";
constant Name bndNodeName    = "$bnd" "binding node";
constant Name cndNodeName    = "$cnd" "conditional component condition";
constant Name dimsNodeName   = "$dims" "dimensions node";
constant Name tydimsNodeName = "$tydims" "type dimensions node";
constant Name subsNodeName   = "$subs" "cref subscripts";
constant Name ccNodeName     = "$cc" "constrain class node";
constant Name eqNodeName     = "$eq" "equation";
constant Name ieqNodeName    = "$ieq" "initial equation";
constant Name alNodeName     = "$al" "algorithm";
constant Name ialNodeName    = "$ial" "initial algorithm";
constant Name optNodeName    = "$opt" "optimization node";
constant Name edNodeName     = "$ed" "external declaration node";
constant Name forNodeName    = "$for" "scope for for-iterators";
constant Name matchNodeName  = "$match" "scope for match exps";
constant Name cloneNodeName  = "$clone" "clone of the reference node";
constant Name origNodeName   = "$original" "the original of the clone";

public function toRef
"@author: adrpo
 turns a node into a ref"
  input Node inNode;
  output Ref outRef;
algorithm
  outRef := arrayCreate(1, inNode);
end toRef;

public function fromRef
"@author: adrpo
 turns a ref into a node"
  input Ref inRef;
  output Node outNode;
algorithm
  outNode := arrayGet(inRef, 1);
end fromRef;

public function updateRef
"@author: adrpo
 sets a node into a ref"
  input Ref inRef;
  input Node inNode;
  output Ref outRef;
algorithm
  outRef := arrayUpdate(inRef, 1, inNode);
end updateRef;

public function id
  input Node inNode;
  output Id id;
algorithm
  FCore.N(id = id) := inNode;
end id;

public function parents
  input Node inNode;
  output Parents p;
algorithm
  FCore.N(parents = p) := inNode;
end parents;

public function hasParents
  input Node inNode;
  output Boolean b;
algorithm
  b := List.isNotEmpty(parents(inNode));
end hasParents;

public function target
"returns a target from a REF node"
  input Node inNode; 
  output Ref outRef;
algorithm
  outRef := match(inNode)
    local Ref r;
    case FCore.N(data = FCore.REF(target = r)) then r;
  end match;
end target;

public function new
  input Name inName;
  input Id inId;
  input Parents inParents;
  input Data inData;
  output Node node;
algorithm
  node := FCore.N(inName, inId, inParents, FCore.emptyCAvlTree, inData);
end new;

public function addImport
"add import to the import table"
  input SCode.Element inImport;
  input ImportTable inImportTable;
  output ImportTable outImportTable;
algorithm
  outImportTable := match(inImport, inImportTable)
    local
      Import imp;
      list<Import> qual_imps, unqual_imps;
      Absyn.Info info;
      Boolean hidden;

    // Unqualified imports
    case (SCode.IMPORT(imp = imp as Absyn.UNQUAL_IMPORT(path = _)),
          FCore.IMPORT_TABLE(hidden, qual_imps, unqual_imps))
      equation
        unqual_imps = imp :: unqual_imps;
      then
        FCore.IMPORT_TABLE(hidden, qual_imps, unqual_imps);

    // Qualified imports
    case (SCode.IMPORT(imp = imp, info = info),
          FCore.IMPORT_TABLE(hidden, qual_imps, unqual_imps))
      equation
        imp = translateQualifiedImportToNamed(imp);
        checkUniqueQualifiedImport(imp, qual_imps, info);
        qual_imps = imp :: qual_imps;
      then
        FCore.IMPORT_TABLE(hidden, qual_imps, unqual_imps);
  end match;
end addImport;

protected function translateQualifiedImportToNamed
  "Translates a qualified import to a named import."
  input Import inImport;
  output Import outImport;
algorithm
  outImport := match(inImport)
    local
      Name name;
      Absyn.Path path;

    // Already named.
    case Absyn.NAMED_IMPORT(name = _) then inImport;

    // Get the last identifier from the import and use that as the name.
    case Absyn.QUAL_IMPORT(path = path)
      equation
        name = Absyn.pathLastIdent(path);
      then
        Absyn.NAMED_IMPORT(name, path);
  end match;
end translateQualifiedImportToNamed;

protected function checkUniqueQualifiedImport
  "Checks that a qualified import is unique, because it's not allowed to have
  qualified imports with the same name."
  input Import inImport;
  input list<Import> inImports;
  input Absyn.Info inInfo;
algorithm
  _ := matchcontinue(inImport, inImports, inInfo)
    local
      Name name;

    case (_, _, _)
      equation
        false = List.isMemberOnTrue(inImport, inImports,
          compareQualifiedImportNames);
      then
        ();

    case (Absyn.NAMED_IMPORT(name = name), _, _)
      equation
        Error.addSourceMessage(Error.MULTIPLE_QUALIFIED_IMPORTS_WITH_SAME_NAME,
          {name}, inInfo);
      then
        fail();

  end matchcontinue;
end checkUniqueQualifiedImport;

protected function compareQualifiedImportNames
  "Compares two qualified imports, returning true if they have the same import
  name, otherwise false."
  input Import inImport1;
  input Import inImport2;
  output Boolean outEqual;
algorithm
  outEqual := matchcontinue(inImport1, inImport2)
    local
      Name name1, name2;

    case (Absyn.NAMED_IMPORT(name = name1), Absyn.NAMED_IMPORT(name = name2))
      equation
        true = stringEqual(name1, name2);
      then
        true;

    else then false;
  end matchcontinue;
end compareQualifiedImportNames;

public function addChildRef
  input Ref inParentRef;
  input Name inName;
  input Ref inChildRef;
protected
  Name n;
  Integer id;
  Parents p;
  Children c;
  Data d;
  Ref parent;
algorithm
  FCore.N(n, id, p, c, d) := fromRef(inParentRef);
  c := avlTreeAdd(c, inName, inChildRef);
  parent := updateRef(inParentRef, FCore.N(n, id, p, c, d)); 
end addChildRef;

public function addImportToRef
  input Ref ref;
  input SCode.Element imp;
protected
  Name n;
  Integer id;
  Parents p;
  Children c;
  Data d;
  SCode.Element e;
  Kind t;
  ImportTable it;
  Ref r;
algorithm
  FCore.N(n, id, p, c, FCore.CL(e, t, it)) := fromRef(ref);
  it := addImport(imp, it);
  r := updateRef(ref, FCore.N(n, id, p, c, FCore.CL(e, t, it))); 
end addImportToRef;

public function addTypesToRef
  input Ref ref;
  input list<DAE.Type> inTys;
protected
  Name n;
  Integer id;
  Parents p;
  Children c;
  Data d;
  SCode.Element e;
  Kind t;
  ImportTable it;
  list<DAE.Type> tys;
  Ref r;
algorithm
  FCore.N(n, id, p, c, FCore.TY(tys)) := fromRef(ref);
  tys := listAppend(inTys, tys);
  // update the child
  r := updateRef(ref, FCore.N(n, id, p, c, FCore.TY(tys)));
end addTypesToRef;

public function addIteratorsToRef
  input Ref ref;
  input Absyn.ForIterators inIterators;
protected
  Name n;
  Integer id;
  Parents p;
  Children c;
  Data d;
  SCode.Element e;
  Kind t;
  Absyn.ForIterators it;
  Ref r;
algorithm
  FCore.N(n, id, p, c, FCore.FS(it)) := fromRef(ref);
  it := listAppend(it, inIterators);
  // update the child
  r := updateRef(ref, FCore.N(n, id, p, c, FCore.FS(it)));
end addIteratorsToRef;


public function name
  input Node n;
  output String name;
algorithm
  name := match(n)
    local String s;
    case (FCore.N(name = s)) then s;
  end match;
end name;

public function data
  input Node n;
  output Data data;
algorithm
  data := match(n)
    local Data d;
    case (FCore.N(data = d)) then d;
  end match;
end data;

public function top
"@author: adrpo
 return the top node ref"
  input Ref inRef;
  output Ref outTop;
algorithm
  outTop := matchcontinue(inRef)
    local
      Ref t;
    
    // already at the top
    case (_)
      equation
        false = hasParents(fromRef(inRef));
      then 
        inRef;
    
        // already at the top
    case (_)
      equation
        true = hasParents(fromRef(inRef));
        t = top(List.first(parents(fromRef(inRef))));
      then 
        t;
  
  end matchcontinue;
end top;

public function children
  input Node inNode; 
  output Children outChildren;
algorithm
  FCore.N(children = outChildren) := inNode;
end children;

public function setChildren
  input Node inNode;
  input  Children inChildren;
  output Node outNode;
protected
  Name n;
  Id i;
  Parents p;
  Children c;
  Data d;
algorithm
  FCore.N(n, i, p, c, d) := inNode;
  outNode := FCore.N(n, i, p, inChildren, d);
end setChildren;

public function child
  input Ref inParentRef;
  input Name inName;
  output Ref outChildRef;
protected
  Children c;
algorithm
  c := children(fromRef(inParentRef));
  outChildRef := avlTreeGet(c, inName);
end child;

public function element2Data
  input SCode.Element inElement;
  input Kind inKind;
  output Data outData;
algorithm
  outData := match(inElement, inKind)
    local
      String n;
      SCode.Final finalPrefix;
      SCode.Replaceable repl;
      SCode.Visibility vis;
      SCode.ConnectorType ct;
      SCode.Redeclare redecl;
      Absyn.InnerOuter io;
      SCode.Attributes attr;
      list<Absyn.Subscript> ad;
      SCode.Parallelism prl;
      SCode.Variability var;
      Absyn.Direction dir;
      Absyn.TypeSpec t;
      SCode.Mod m;
      SCode.Comment comment;
      Absyn.Info info;
      Option<Absyn.Exp> condition;
      Data nd;

    // a component
    case (SCode.COMPONENT(n,SCode.PREFIXES(vis,redecl,finalPrefix,io,repl),
                                    attr as SCode.ATTR(ad,ct,prl,var,dir),
                                    t,m,comment,condition,info), _)
      equation
        nd = FCore.CO(inElement, 
                DAE.TYPES_VAR(
                  n, 
                  DAE.ATTR(ct,prl,var,dir,io,vis),
                  DAE.T_UNKNOWN_DEFAULT,
                  DAE.UNBOUND(),NONE()),
                FCore.S_UNTYPED(),
                inKind);
      then
        nd;
  
  end match;
end element2Data;

public function dataStr
  input Data inData;
  output String outStr;
algorithm
  outStr := match(inData)
    local Name n;
    case (FCore.TOP()) then "TOP";
    case (FCore.CL(e = SCode.CLASS(classDef = SCode.CLASS_EXTENDS(baseClassName = _)))) then "CE";
    case (FCore.CL(e = _)) then "C";
    case (FCore.CO(e = _)) then "c";
    case (FCore.EX(_)) then "E";
    case (FCore.DE(_)) then "D";
    case (FCore.DU(_)) then "U";
    case (FCore.TY(_)) then "TY";
    case (FCore.AL(_, _)) then "ALG";
    case (FCore.EQ(_, _)) then "EQ";
    case (FCore.OT(_, _)) then "OPT";
    case (FCore.ED(_)) then "ED";
    case (FCore.FS(_)) then "FS";
    case (FCore.FI(_)) then "FI";
    case (FCore.MS(_)) then "MS";
    case (FCore.MO(_)) then "M";
    case (FCore.EXP(name=n)) then n;
    case (FCore.DIMS(name=n)) then n;
    case (FCore.CR(_)) then "r";
    case (FCore.CC(_)) then "CC";
    case (FCore.ND()) then "N";
    case (FCore.REF(_)) then "REF";
    case (FCore.CLONE(_)) then "CLONE";
    else "UKNOWN NODE DATA";
  end match;
end dataStr;

public function toStr
  input Node inNode;
  output String outStr;
algorithm
  outStr := matchcontinue(inNode)
    local
     Name n;
     Id i;
     Parents p;
     Children c;
     Data d;

    case (FCore.N(n, i, p, c, d))
      equation
        outStr = 
           "[i:" +& intString(i) +& "] " +& 
           "[p:" +& stringDelimitList(List.map(List.map(List.map(p, fromRef), id), intString), ", ") +& "] " +&
           "[n:" +& name(inNode) +& "] " +& 
           "[d:" +& dataStr(d) +& "]";
      then
        outStr;
    
    else "Unhandled node!";
  
  end matchcontinue;
end toStr;

public function toPathStr
"returns the path from top to this node"
  input Node inNode;
  output String outStr;
algorithm
  outStr := matchcontinue(inNode)
    local
     Name n;
     Id id;
     Parents p;
     Children c;
     Data d;
     Ref nr;
     String s;
 
    // top node
    case (FCore.N(n, id, {}, c, d))
      equation
        outStr = name(inNode);
      then
        outStr;
    
    case (FCore.N(n, id, nr::_, c, d))
      equation
        true = hasParents(fromRef(nr));
        s = toPathStr(fromRef(nr));
        outStr = s +& "." +& name(inNode);
      then
        outStr;
        
    case (FCore.N(n, id, nr::_, c, d))
      equation
        false = hasParents(fromRef(nr));
        outStr = "." +& name(inNode);
      then
        outStr;
  end matchcontinue;
end toPathStr;

public function isImplicitScope
"anything that is not top, class or a component is an implicit scope!"
  input Node inNode; 
  output Boolean b;
algorithm
  b := match(inNode)
    case FCore.N(data = FCore.TOP()) then false;
    case FCore.N(data = FCore.CL(e = _)) then false;
    case FCore.N(data = FCore.CO(e = _)) then false;
    case FCore.N(data = FCore.FS(fis = _)) then false;
    case FCore.N(data = FCore.MS(e = _)) then false;
    else true;
  end match;
end isImplicitScope;

public function isRefImplicitScope
"anything that is not a class or a component is an implicit scope!"
  input Ref inRef; 
  output Boolean b;
algorithm
  b := isImplicitScope(fromRef(inRef));
end isRefImplicitScope;

public function isEncapsulated
  input Node inNode; 
  output Boolean b;
algorithm
  b := match(inNode)
    case FCore.N(data = FCore.CL(e = SCode.CLASS(encapsulatedPrefix = SCode.ENCAPSULATED()))) then true;
    else false;
  end match;
end isEncapsulated;

public function isReference
  input Node inNode; 
  output Boolean b;
algorithm
  b := match(inNode)
    case FCore.N(data = FCore.REF(target = _)) then true;
    else false;
  end match;
end isReference;

public function isUserDefined
  input Node inNode; 
  output Boolean b;
algorithm
  b := matchcontinue(inNode)
    local Ref p;
    case FCore.N(data = FCore.CL(kind = FCore.USERDEFINED())) then true;
    case FCore.N(data = FCore.CO(kind = FCore.USERDEFINED())) then true;
    // any parent is userdefined?
    case _
      equation
        true = hasParents(inNode);
        p::_ = parents(inNode);
        b = isRefUserDefined(p);
      then
        b;
    else false; 
  end matchcontinue;
end isUserDefined;

public function isTop
  input Node inNode; 
  output Boolean b;
algorithm
  b := match(inNode)
    case FCore.N(data = FCore.TOP()) then true;
    else false; 
  end match;
end isTop;

public function isExtends
  input Node inNode; 
  output Boolean b;
algorithm
  b := match(inNode)
    case FCore.N(data = FCore.EX(e = _)) then true;
    else false;
  end match;
end isExtends;

public function isDerived
  input Node inNode; 
  output Boolean b;
algorithm
  b := match(inNode)
    case FCore.N(data = FCore.DE(d = _)) then true;
    else false;
  end match;
end isDerived;

public function isClass
  input Node inNode; 
  output Boolean b;
algorithm
  b := match(inNode)
    case FCore.N(data = FCore.CL(e = _)) then true;
    else false;
  end match;
end isClass;

public function isClassExtends
  input Node inNode; 
  output Boolean b;
algorithm
  b := match(inNode)
    case FCore.N(data = FCore.CL(e = SCode.CLASS(classDef = SCode.CLASS_EXTENDS(baseClassName = _)))) then true;
    else false;
  end match;
end isClassExtends;

public function isComponent
  input Node inNode; 
  output Boolean b;
algorithm
  b := match(inNode)
    case FCore.N(data = FCore.CO(e = _)) then true;
    else false;
  end match;
end isComponent;

public function isConstrainClass
  input Node inNode; 
  output Boolean b;
algorithm
  b := match(inNode)
    case FCore.N(data = FCore.CC(cc = _)) then true;
    else false;
  end match;
end isConstrainClass;

public function isCref
  input Node inNode; 
  output Boolean b;
algorithm
  b := match(inNode)
    case FCore.N(data = FCore.CR(r = _)) then true;
    else false;
  end match;
end isCref;

public function isBasicType
  input Node inNode; 
  output Boolean b;
algorithm
  b := match(inNode)
    case FCore.N(data = FCore.CL(kind = FCore.BASIC_TYPE())) then true;
    else false;
  end match;
end isBasicType;

public function isBuiltin
  input Node inNode; 
  output Boolean b;
algorithm
  b := match(inNode)
    case FCore.N(data = FCore.CL(kind = FCore.BUILTIN())) then true;
    case FCore.N(data = FCore.CO(kind = FCore.BUILTIN())) then true;
    else false;
  end match;
end isBuiltin;

public function isFunction
  input Node inNode; 
  output Boolean b;
algorithm
  b := matchcontinue(inNode)
    local
      SCode.Element e;
    case FCore.N(data = FCore.CL(e = e))
      equation
        true = SCode.isFunction(e);
      then true;
    else false;
  end matchcontinue;
end isFunction;

public function isRecord
  input Node inNode; 
  output Boolean b;
algorithm
  b := matchcontinue(inNode)
    local
      SCode.Element e;
    case FCore.N(data = FCore.CL(e = e))
      equation
        true = SCode.isRecord(e);
      then true;
    else false;
  end matchcontinue;
end isRecord;

public function isSection
  input Node inNode;
  output Boolean b;
algorithm
  b := match(inNode)
    case (FCore.N(data = FCore.AL(name = _))) then true;
    case (FCore.N(data = FCore.EQ(name = _))) then true;
    else false;
  end match;
end isSection;

public function isMod
  input Node inNode;
  output Boolean b;
algorithm
  b := match(inNode)
    case (FCore.N(data = FCore.MO(m = _))) then true;
    else false;
  end match;
end isMod;

public function isInMod
  input Node inNode; 
  output Boolean b;
algorithm
  b := match(inNode)
    local
      Scope s;
      Boolean b1, b2;
    
    case _
      equation
        s = originalScope(toRef(inNode));
        b1 = List.fold(List.map(s, isRefMod), boolOr, false);
        s = contextualScope(toRef(inNode));
        b2 = List.fold(List.map(s, isRefMod), boolOr, false);
        b = boolOr(b1, b2);
      then
        b;
  
  end match;
end isInMod;

public function isInSection
  input Node inNode; 
  output Boolean b;
algorithm
  b := match(inNode)
    local
      Scope s;
      Boolean b1, b2;
    
    case _
      equation
        s = originalScope(toRef(inNode));
        b1 = List.fold(List.map(s, isRefSection), boolOr, false);
        s = contextualScope(toRef(inNode));
        b2 = List.fold(List.map(s, isRefSection), boolOr, false);
        b = boolOr(b1, b2);
      then
        b;
  
  end match;
end isInSection;

public function originalScope
"@author:
 return the scope from this ref to the top as a list of references.
 NOTE: 
   the starting point reference is included and 
   the scope is returned reversed, from leafs 
   to top"
  input Ref inRef;
  output Scope outScope;
algorithm
  outScope := originalScope_dispatch(inRef, {});
end originalScope;

public function originalScope_dispatch
"@author:
 return the scope from this ref to the top as a list of references.
 NOTE: 
   the starting point reference is included and 
   the scope is returned reversed, from leafs 
   to top"
  input Ref inRef;
  input Scope inAcc;
  output Scope outScope;
algorithm
  outScope := matchcontinue(inRef, inAcc)
    local
      Scope acc;
      Ref r;
    
    // top
    case (_, acc)
      equation
        true = isTop(fromRef(inRef));
      then
        listReverse(inRef::acc);
    
    // not top
    case (_, acc)
      equation
        r = original(parents(fromRef(inRef)));
        acc = originalScope_dispatch(r, inRef::acc);
      then
        acc;
  
  end matchcontinue;
end originalScope_dispatch;

public function original
"@author:
 return the original parent from the parents (the last one)"
  input Parents inParents;
  output Ref outOriginal;
algorithm
  outOriginal := List.last(inParents);
end original;

public function contextualScope
"@author:
 return the scope from this ref to the top as a list of references.
 NOTE: 
   the starting point reference is included and 
   the scope is returned reversed, from leafs 
   to top"
  input Ref inRef;
  output Scope outScope;
algorithm
  outScope := contextualScope_dispatch(inRef, {});
end contextualScope;

public function contextualScope_dispatch
"@author:
 return the scope from this ref to the top as a list of references.
 NOTE: 
   the starting point reference is included and 
   the scope is returned reversed, from leafs 
   to top"
  input Ref inRef;
  input Scope inAcc;
  output Scope outScope;
algorithm
  outScope := matchcontinue(inRef, inAcc)
    local
      Scope acc;
      Ref r;
    
    // top
    case (_, acc)
      equation
        true = isTop(fromRef(inRef));
      then
        listReverse(inRef::acc);
    
    // not top
    case (_, acc)
      equation
        r = contextual(parents(fromRef(inRef)));
        acc = contextualScope_dispatch(r, inRef::acc);
      then
        acc;
  
  end matchcontinue;
end contextualScope_dispatch;

public function contextual
"@author:
 return the contextual parent from the parents (the first one)"
  input Parents inParents;
  output Ref outContextual;
algorithm
  outContextual := List.first(inParents);
end contextual;

public function filter
"@author: adrpo
 filter the children of the given
 reference by the given filter"
  input Ref inRef;
  input Filter inFilter; 
  output Refs filtered;
  partial function Filter
    input Ref inRef;
    output Boolean select;
  end Filter;
algorithm
  filtered := match(inRef, inFilter)
    local
      Refs rfs;
      Children c;
    
    case (_, _)
      equation
        c = children(fromRef(inRef));
        rfs = getAvlValues(c);
        rfs = List.filterOnTrue(rfs, inFilter); 
      then 
        rfs;
  
  end match;
end filter;

public function isRefExtends
  input Ref inRef; 
  output Boolean b;
algorithm
  b := isExtends(fromRef(inRef));
end isRefExtends;

public function isRefDerived
  input Ref inRef; 
  output Boolean b;
algorithm
  b := isDerived(fromRef(inRef));
end isRefDerived;

public function isRefComponent
  input Ref inRef; 
  output Boolean b;
algorithm
  b := isComponent(fromRef(inRef));
end isRefComponent;

public function isRefConstrainClass
  input Ref inRef; 
  output Boolean b;
algorithm
  b := isConstrainClass(fromRef(inRef));
end isRefConstrainClass;

public function isRefClass
  input Ref inRef; 
  output Boolean b;
algorithm
  b := isClass(fromRef(inRef));
end isRefClass;

public function isRefClassExtends
  input Ref inRef; 
  output Boolean b;
algorithm
  b := isClassExtends(fromRef(inRef));
end isRefClassExtends;

public function isRefCref
  input Ref inRef; 
  output Boolean b;
algorithm
  b := isCref(fromRef(inRef));
end isRefCref;

public function isRefReference
  input Ref inRef; 
  output Boolean b;
algorithm
  b := isReference(fromRef(inRef));
end isRefReference;

public function isRefUserDefined
  input Ref inRef; 
  output Boolean b;
algorithm
  b := isUserDefined(fromRef(inRef));
end isRefUserDefined;

public function isRefTop
  input Ref inRef; 
  output Boolean b;
algorithm
  b := isTop(fromRef(inRef));
end isRefTop;

public function isRefBasicType
  input Ref inRef; 
  output Boolean b;
algorithm
  b := isBasicType(fromRef(inRef));
end isRefBasicType;

public function isRefBuiltin
  input Ref inRef; 
  output Boolean b;
algorithm
  b := isBuiltin(fromRef(inRef));
end isRefBuiltin;

public function isRefFunction
  input Ref inRef; 
  output Boolean b;
algorithm
  b := isFunction(fromRef(inRef));
end isRefFunction;

public function isRefRecord
  input Ref inRef; 
  output Boolean b;
algorithm
  b := isRecord(fromRef(inRef));
end isRefRecord;

public function isRefSection
  input Ref inRef; 
  output Boolean b;
algorithm
  b := isSection(fromRef(inRef));
end isRefSection;

public function isRefMod
  input Ref inRef; 
  output Boolean b;
algorithm
  b := isMod(fromRef(inRef));
end isRefMod;

public function isRefInSection
  input Ref inRef; 
  output Boolean b;
algorithm
  b := isInSection(fromRef(inRef));
end isRefInSection;

public function isRefInMod
  input Ref inRef; 
  output Boolean b;
algorithm
  b := isInMod(fromRef(inRef));
end isRefInMod;

public function dfs
"@author: adrpo
 return all refs as given by 
 depth first search"
  input Ref inRef;
  output Refs outRefs;
algorithm
  outRefs := match(inRef)
    local
      Refs refs;
      Children c;
    
    case _
      equation
        c = children(fromRef(inRef));
        refs = getAvlValues(c);
        refs = List.flatten(List.map(refs, dfs));
        refs = inRef::refs;
      then
        refs;
  
  end match;
end dfs;

public function dfs_filter
"@author: adrpo
 return all refs as given by 
 reversed depth first search 
 filtered by the given filter 
 function"
  input Ref inRef;
  input Filter inFilter;
  output Refs outRefs;
  partial function Filter
    input Ref inRef;
    output Boolean select;
  end Filter;
algorithm
  outRefs := match(inRef, inFilter)
    local
      Refs refs;
      Boolean b;
    
    case (_, _)
      equation
        b = inFilter(inRef);
        refs = List.consOnTrue(b, inRef, {});
        refs = dfs_filter_helper(children(fromRef(inRef)), inFilter, refs);
      then
        refs;
  
  end match;
end dfs_filter;

public function dfs_filter_helper
  input AvlTree inTree;
  input Filter inFilter;
  input list<AvlValue> inAcc;
  output list<AvlValue> outAvlValues;
  partial function Filter
    input AvlValue inValue;
    output Boolean select;
  end Filter;
algorithm
  outAvlValues := match(inTree, inFilter, inAcc)
    local
      list<AvlValue> acc;
      AvlValue v;
      AvlTree t, tl, tr;
      Boolean b;
    
    // empty tree
    case (FCore.CAVLTREENODE(NONE(), _, NONE(), NONE()), _, _) 
      then 
        inAcc;
    
    // leaf
    case (FCore.CAVLTREENODE(SOME(FCore.CAVLTREEVALUE(_, v)), _, NONE(), NONE()), _, acc)
      equation
        b = inFilter(v);
        acc = List.consOnTrue(b, v, acc);
        acc = dfs_filter_helper(children(fromRef(v)), inFilter, acc);
      then 
        acc;
        
    // non-leaf on left
    case (FCore.CAVLTREENODE(SOME(FCore.CAVLTREEVALUE(_, v)), _, SOME(t), NONE()), _, acc)
      equation
        b = inFilter(v);
        acc = List.consOnTrue(b, v, acc);
        acc = dfs_filter_helper(children(fromRef(v)), inFilter, acc);
        acc = dfs_filter_helper(t, inFilter, acc);
      then 
        acc;
    
    // non-leaf on right
    case (FCore.CAVLTREENODE(SOME(FCore.CAVLTREEVALUE(_, v)), _, NONE(), SOME(t)), _, acc)
      equation
        b = inFilter(v);
        acc = List.consOnTrue(b, v, acc);
        acc = dfs_filter_helper(children(fromRef(v)), inFilter, acc);
        acc = dfs_filter_helper(t, inFilter, acc);
      then 
        acc;
    
    // non-leaf on both left and right
    case (FCore.CAVLTREENODE(SOME(FCore.CAVLTREEVALUE(_, v)), _, SOME(tl), SOME(tr)), _, acc)
      equation
        b = inFilter(v);
        acc = List.consOnTrue(b, v, acc);
        acc = dfs_filter_helper(children(fromRef(v)), inFilter, acc);
        acc = dfs_filter_helper(tl, inFilter, acc);
        acc = dfs_filter_helper(tr, inFilter, acc);
      then
        acc;
  
  end match;
end dfs_filter_helper;

public function apply
"@author: adrpo
 apply a function on all the subtree pointed by given ref.
 the order of application is dfs."
  input Ref inRef;
  input Apply inApply;
  partial function Apply
    input Ref inRef;
  end Apply;
algorithm
  _ := match(inRef, inApply)
    local
      Refs refs;
      Boolean b;
    
    case (_, _)
      equation
        inApply(inRef);
        apply_helper(children(fromRef(inRef)), inApply);
      then
        ();
  
  end match;
end apply;

public function apply_helper
  input AvlTree inTree;
  input Apply inApply;
  partial function Apply
    input AvlValue inValue;
  end Apply;
algorithm
  _ := match(inTree, inApply)
    local
      list<AvlValue> acc;
      AvlValue v;
      AvlTree t, tl, tr;
      Boolean b;
    
    // empty tree
    case (FCore.CAVLTREENODE(NONE(), _, NONE(), NONE()), _) 
      then 
        ();
    
    // leaf
    case (FCore.CAVLTREENODE(SOME(FCore.CAVLTREEVALUE(_, v)), _, NONE(), NONE()), _)
      equation
        inApply(v);
        apply_helper(children(fromRef(v)), inApply);
      then 
        ();
        
    // non-leaf on left
    case (FCore.CAVLTREENODE(SOME(FCore.CAVLTREEVALUE(_, v)), _, SOME(t), NONE()), _)
      equation
        inApply(v);
        apply_helper(children(fromRef(v)), inApply);
        apply_helper(t, inApply);
      then 
        ();
    
    // non-leaf on right
    case (FCore.CAVLTREENODE(SOME(FCore.CAVLTREEVALUE(_, v)), _, NONE(), SOME(t)), _)
      equation
        inApply(v);
        apply_helper(children(fromRef(v)), inApply);
        apply_helper(t, inApply);
      then 
        ();
    
    // non-leaf on both left and right
    case (FCore.CAVLTREENODE(SOME(FCore.CAVLTREEVALUE(_, v)), _, SOME(tl), SOME(tr)), _)
      equation
        inApply(v);
        apply_helper(children(fromRef(v)), inApply);
        apply_helper(tl, inApply);
        apply_helper(tr, inApply);
      then
        ();
  
  end match;
end apply_helper;

public function apply1
"@author: adrpo
 apply a function on all the subtree pointed by given ref.
 the order of application is dfs."
  input Ref inRef;
  input Apply inApply;
  input ExtraArg inExtraArg;
  output ExtraArg outExtraArg;
  partial function Apply
    input Ref inRef;
    input ExtraArg inExtraArg;
    output ExtraArg outExtraArg;
  end Apply;
  replaceable type ExtraArg subtypeof Any;
algorithm
  outExtraArg := match(inRef, inApply, inExtraArg)
    local
      Refs refs;
      Boolean b;
      ExtraArg a;
    
    case (_, _, a)
      equation
        a = inApply(inRef, a);
        a = apply_helper1(children(fromRef(inRef)), inApply, a);
      then
        a;
  
  end match;
end apply1;

public function apply_helper1
  input AvlTree inTree;
  input Apply inApply;
  input ExtraArg inExtraArg;
  output ExtraArg outExtraArg;
  partial function Apply
    input AvlValue inRef;
    input ExtraArg inExtraArg;
    output ExtraArg outExtraArg;
  end Apply;
  replaceable type ExtraArg subtypeof Any;
algorithm
  outExtraArg := match(inTree, inApply, inExtraArg)
    local
      list<AvlValue> acc;
      AvlValue v;
      AvlTree t, tl, tr;
      Boolean b;
      ExtraArg a;
    
    // empty tree
    case (FCore.CAVLTREENODE(NONE(), _, NONE(), NONE()), _, a) 
      then 
        a;
    
    // leaf
    case (FCore.CAVLTREENODE(SOME(FCore.CAVLTREEVALUE(_, v)), _, NONE(), NONE()), _, a)
      equation
        a = inApply(v, a);
        a = apply_helper1(children(fromRef(v)), inApply, a);
      then 
        a;
        
    // non-leaf on left
    case (FCore.CAVLTREENODE(SOME(FCore.CAVLTREEVALUE(_, v)), _, SOME(t), NONE()), _, a)
      equation
        a = inApply(v, a);
        a = apply_helper1(children(fromRef(v)), inApply, a);
        a = apply_helper1(t, inApply, a);
      then
        a;
    
    // non-leaf on right
    case (FCore.CAVLTREENODE(SOME(FCore.CAVLTREEVALUE(_, v)), _, NONE(), SOME(t)), _, a)
      equation
        a = inApply(v, a);
        a = apply_helper1(children(fromRef(v)), inApply, a);
        a = apply_helper1(t, inApply, a);
      then 
        a;
    
    // non-leaf on both left and right
    case (FCore.CAVLTREENODE(SOME(FCore.CAVLTREEVALUE(_, v)), _, SOME(tl), SOME(tr)), _, a)
      equation
        a = inApply(v, a);
        a = apply_helper1(children(fromRef(v)), inApply, a);
        a = apply_helper1(tl, inApply, a);
        a = apply_helper1(tr, inApply, a);
      then
        a;
  
  end match;
end apply_helper1;

public function hasImports
  input Node inNode;
  output Boolean b;
algorithm
  b := match(inNode)
    local list<Import> qi, uqi;
    case (FCore.N(data = FCore.CL(importTable = FCore.IMPORT_TABLE(_, qi, uqi))))
      equation
        b = boolOr(List.isNotEmpty(qi), List.isNotEmpty(uqi));
      then
        b;
    else false;
  end match;
end hasImports;

public function imports
  input Node inNode;
  output list<Import> outQualifiedImports;
  output list<Import> outUnQualifiedImports;
algorithm
  (outQualifiedImports, outUnQualifiedImports) := match(inNode)
    local list<Import> qi, uqi;
    case (FCore.N(data = FCore.CL(importTable = FCore.IMPORT_TABLE(_, qi, uqi)))) then (qi, uqi);
    else ({}, {});
  end match;
end imports;

public function extendsRefs
  input Ref inRef;
  output Refs outRefs;
algorithm
  outRefs := matchcontinue(inRef)
    local
      Refs refs;
    
    case (_)
      equation
        // we have a class
        true = isRefClass(inRef);
        // see if it has extends or derived
        refs = listAppend(filter(inRef, isRefExtends), filter(inRef, isRefDerived));
        refs = List.flatten(List.map1(refs, filter, isRefReference));
      then
        refs;
    
    else {}; 
  
  end matchcontinue;
end extendsRefs;

public function cloneRef
"@author: adrpo
 clone a node ref entire subtree
 the clone will have 2 parents
 {inParentRef, originalParentRef}"
  input Name inName;
  input Ref inRef;
  input Ref inParentRef;
  input Graph inGraph;
  output Graph outGraph;
  output Ref outRef;
algorithm
  (outGraph, outRef) := match(inName, inRef, inParentRef, inGraph)
    local
      Node n;
      Graph g;
      Ref r;
    
    case (_, _, _, g)
      equation
        (g, r) = clone(fromRef(inRef), inParentRef, g);
        addChildRef(inParentRef, inName, r);
      then
        (g, r);
  
  end match;
end cloneRef;

public function clone
"@author: adrpo
 clone a node entire subtree
 the clone will have 2 parents
 {inParentRef, originalParentRef}"
  input Node inNode;
  input Ref inParentRef;
  input Graph inGraph;
  output Graph outGraph;
  output Ref outRef;
algorithm
  (outGraph, outRef) := match(inNode, inParentRef, inGraph)
    local
      Node n;
      Graph g;
      Ref r;
      Name name;
      Id id;
      Parents parents;
      Children children;
      Data data;
    
    case (FCore.N(name, id, parents, children, data), _, g)
      equation
        // add parent
        parents = inParentRef::parents;
        // create node clone
        (g, n as FCore.N(name, id, parents, _, data)) = FGraph.node(g, name, parents, data);
        // make the reference to the new node
        r = toRef(n);
        // clone children
        (g, children) = cloneTree(children, r, g);
        // set the children in the new node
        r = updateRef(r, FCore.N(name, id, parents, children, data)); 
      then
        (g, r);
  
  end match;
end clone;

public function cloneTree
"@author: adrpo
 clone a node entire subtree
 the clone will have 2 parents
 {inParentRef, originalParentRef}"
  input Children inChildren;
  input Ref inParentRef;
  input Graph inGraph;
  output Graph outGraph;
  output Children outChildren;
algorithm
  (outGraph, outChildren) := match(inChildren, inParentRef, inGraph)
    local
      Integer h;
      Option<AvlTree> l, r;
      Option<AvlTreeValue> v;
      Graph g;
    
    // tree
    case (FCore.CAVLTREENODE(v, h, l, r), _, g)
      equation
        (g, v) = cloneTreeValueOpt(v, inParentRef, g);
        (g, l) = cloneTreeOpt(l, inParentRef, g);
        (g, r) = cloneTreeOpt(r, inParentRef, g);
      then
        (g, FCore.CAVLTREENODE(v, h, l, r));
          
  end match;
end cloneTree;

public function cloneTreeOpt
"@author: adrpo
 clone a node entire subtree
 the clone will have 2 parents
 {inParentRef, originalParentRef}"
  input Option<AvlTree> inTreeOpt;
  input Ref inParentRef;
  input Graph inGraph;
  output Graph outGraph;
  output Option<AvlTree> outTreeOpt;
algorithm
  (outGraph, outTreeOpt) := match(inTreeOpt, inParentRef, inGraph)
    local
      Ref ref;
      Name name;
      Integer h;
      AvlTree t;
      Graph g;
    
    // empty tree
    case (NONE(), _, _) then (inGraph, NONE());
    // some tree
    case (SOME(t), _, _)
      equation
        (g, t) = cloneTree(t, inParentRef, inGraph);
      then 
        (g, SOME(t)); 
  
  end match;
end cloneTreeOpt;

public function cloneTreeValueOpt
"@author: adrpo
 clone a tree value"
  input Option<AvlTreeValue> inTreeValueOpt;
  input Ref inParentRef;
  input Graph inGraph;
  output Graph outGraph;
  output Option<AvlTreeValue> outTreeValueOpt;
algorithm
  (outGraph, outTreeValueOpt) := match(inTreeValueOpt, inParentRef, inGraph)
    local
      Ref ref;
      Name name;
      AvlTreeValue v;
      Graph g;
    
    // empty value
    case (NONE(), _, _) then (inGraph, NONE());
    // some value
    case (SOME(FCore.CAVLTREEVALUE(name, ref)), _, _)
      equation
        (g, ref) = cloneRef(name, ref, inParentRef, inGraph);
      then 
        (g, SOME(FCore.CAVLTREEVALUE(name, ref)));
  
  end match;
end cloneTreeValueOpt;

// ************************ AVL Tree implementation ***************************
// ************************ AVL Tree implementation ***************************
// ************************ AVL Tree implementation ***************************
// ************************ AVL Tree implementation ***************************

public function keyStr "prints a key to a string"
input AvlKey k;
output String str;
algorithm
  str := k;
end keyStr;

public function valueStr "prints a Value to a string"
  input AvlValue v;
  output String str;
algorithm
  str := match(v)
    local
      String name;

    case(_) then "";

  end match;
end valueStr;

/* Generic Code below */
public function avlTreeNew "Return an empty tree"
  output AvlTree tree;
  annotation(__OpenModelica_EarlyInline = true);
algorithm
  tree := FCore.emptyCAvlTree;
end avlTreeNew;

public function avlTreeAdd
  "Help function to avlTreeAdd."
  input AvlTree inAvlTree;
  input AvlKey inKey;
  input AvlValue inValue;
  output AvlTree outAvlTree;
algorithm
  outAvlTree := match (inAvlTree,inKey,inValue)
    local
      AvlKey key,rkey;
      AvlValue value;

    // empty tree
    case (FCore.CAVLTREENODE(value = NONE(),left = NONE(),right = NONE()),key,value)
      then FCore.CAVLTREENODE(SOME(FCore.CAVLTREEVALUE(key,value)),1,NONE(),NONE());

    case (FCore.CAVLTREENODE(value = SOME(FCore.CAVLTREEVALUE(key=rkey))),key,value)
      then balance(avlTreeAdd2(inAvlTree,stringCompare(key,rkey),key,value));

    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR, {"Env.avlTreeAdd failed"});
      then fail();
  end match;
end avlTreeAdd;

public function avlTreeAdd2
  "Help function to avlTreeAdd."
  input AvlTree inAvlTree;
  input Integer keyComp "0=get value from current node, 1=search right subtree, -1=search left subtree";
  input AvlKey inKey;
  input AvlValue inValue;
  output AvlTree outAvlTree;
algorithm
  outAvlTree := match (inAvlTree,keyComp,inKey,inValue)
    local
      AvlKey key,rkey;
      AvlValue value;
      Option<AvlTree> left,right;
      Integer h;
      AvlTree t_1,t;
      Option<AvlTreeValue> oval;

    /*/ Don't allow replacing of nodes.
    case (_, 0, key, _)
      equation
        info = getItemInfo(inValue);
        Error.addSourceMessage(Error.DOUBLE_DECLARATION_OF_ELEMENTS,
          {inKey}, info);
      then
        fail();*/

    // replace this node
    case (FCore.CAVLTREENODE(value = SOME(FCore.CAVLTREEVALUE(key=rkey)),height=h,left = left,right = right),0,key,value)
      equation
        // inactive for now, but we should check if we don't replace a class with a var or vice-versa!
        // checkValueReplacementCompatible(rval, value);
      then
        FCore.CAVLTREENODE(SOME(FCore.CAVLTREEVALUE(rkey,value)),h,left,right);

    // insert to right
    case (FCore.CAVLTREENODE(value = oval,height=h,left = left,right = right),1,key,value)
      equation
        t = createEmptyAvlIfNone(right);
        t_1 = avlTreeAdd(t, key, value);
      then
        FCore.CAVLTREENODE(oval,h,left,SOME(t_1));

    // insert to left subtree
    case (FCore.CAVLTREENODE(value = oval,height=h,left = left ,right = right),-1,key,value)
      equation
        t = createEmptyAvlIfNone(left);
        t_1 = avlTreeAdd(t, key, value);
      then
        FCore.CAVLTREENODE(oval,h,SOME(t_1),right);

  end match;
end avlTreeAdd2;

protected function createEmptyAvlIfNone "Help function to AvlTreeAdd2"
  input Option<AvlTree> t;
  output AvlTree outT;
algorithm
  outT := match (t)
    case(NONE()) then FCore.CAVLTREENODE(NONE(),0,NONE(),NONE());
    case(SOME(outT)) then outT;
  end match;
end createEmptyAvlIfNone;

protected function nodeValue "return the node value"
  input AvlTree bt;
  output AvlValue v;
algorithm
  v := match (bt)
    case(FCore.CAVLTREENODE(value=SOME(FCore.CAVLTREEVALUE(_,v)))) then v;
  end match;
end nodeValue;

protected function balance "Balances a AvlTree"
  input AvlTree inBt;
  output AvlTree outBt;
algorithm
  outBt := match (inBt)
    local Integer d; AvlTree bt;
    case (bt)
      equation
        d = differenceInHeight(bt);
        bt = doBalance(d,bt);
      then bt;
  end match;
end balance;

protected function doBalance "perform balance if difference is > 1 or < -1"
  input Integer difference;
  input AvlTree inBt;
  output AvlTree outBt;
algorithm
  outBt := match (difference,inBt)
    local AvlTree bt;
    case(-1,bt) then computeHeight(bt);
    case(0,bt) then computeHeight(bt);
    case(1,bt) then computeHeight(bt);
      /* d < -1 or d > 1 */
    case(_,bt)
      equation
        bt = doBalance2(difference < 0,bt);
      then bt;
  end match;
end doBalance;

protected function doBalance2 "help function to doBalance"
  input Boolean differenceIsNegative;
  input AvlTree inBt;
  output AvlTree outBt;
algorithm
  outBt := match (differenceIsNegative,inBt)
    local AvlTree bt;
    case (true,bt)
      equation
        bt = doBalance3(bt);
        bt = rotateLeft(bt);
      then bt;
    case (false,bt)
      equation
        bt = doBalance4(bt);
        bt = rotateRight(bt);
      then bt;
  end match;
end doBalance2;

protected function doBalance3 "help function to doBalance2"
  input AvlTree inBt;
  output AvlTree outBt;
algorithm
  outBt := matchcontinue(inBt)
    local
      AvlTree rr,bt;
    case(bt)
      equation
        true = differenceInHeight(getOption(rightNode(bt))) > 0;
        rr = rotateRight(getOption(rightNode(bt)));
        bt = setRight(bt,SOME(rr));
      then bt;
    else inBt;
  end matchcontinue;
end doBalance3;

protected function doBalance4 "help function to doBalance2"
  input AvlTree inBt;
  output AvlTree outBt;
algorithm
  outBt := matchcontinue(inBt)
    local
      AvlTree rl,bt;
    case (bt)
      equation
        true = differenceInHeight(getOption(leftNode(bt))) < 0;
        rl = rotateLeft(getOption(leftNode(bt)));
        bt = setLeft(bt,SOME(rl));
      then bt;
    else inBt;
  end matchcontinue;
end doBalance4;

protected function setRight "set right treenode"
  input AvlTree node;
  input Option<AvlTree> right;
  output AvlTree outNode;
algorithm
  outNode := match (node,right)
   local Option<AvlTreeValue> value;
    Option<AvlTree> l,r;
    Integer height;
    case(FCore.CAVLTREENODE(value,height,l,r),_) then FCore.CAVLTREENODE(value,height,l,right);
  end match;
end setRight;

protected function setLeft "set left treenode"
  input AvlTree node;
  input Option<AvlTree> left;
  output AvlTree outNode;
algorithm
  outNode := match (node,left)
  local Option<AvlTreeValue> value;
    Option<AvlTree> l,r;
    Integer height;
    case(FCore.CAVLTREENODE(value,height,l,r),_) then FCore.CAVLTREENODE(value,height,left,r);
  end match;
end setLeft;

protected function leftNode "Retrieve the left subnode"
  input AvlTree node;
  output Option<AvlTree> subNode;
algorithm
  subNode := match(node)
    case(FCore.CAVLTREENODE(left = subNode)) then subNode;
  end match;
end leftNode;

protected function rightNode "Retrieve the right subnode"
  input AvlTree node;
  output Option<AvlTree> subNode;
algorithm
  subNode := match(node)
    case(FCore.CAVLTREENODE(right = subNode)) then subNode;
  end match;
end rightNode;

protected function exchangeLeft "help function to balance"
  input AvlTree inNode;
  input AvlTree inParent;
  output AvlTree outParent "updated parent";
algorithm
  outParent := match(inNode,inParent)
    local
      AvlTree bt,node,parent;

    case(node,parent) equation
      parent = setRight(parent,leftNode(node));
      parent = balance(parent);
      node = setLeft(node,SOME(parent));
      bt = balance(node);
    then bt;
  end match;
end exchangeLeft;

protected function exchangeRight "help function to balance"
  input AvlTree inNode;
  input AvlTree inParent;
  output AvlTree outParent "updated parent";
algorithm
  outParent := match(inNode,inParent)
  local AvlTree bt,node,parent;
    case(node,parent) equation
      parent = setLeft(parent,rightNode(node));
      parent = balance(parent);
      node = setRight(node,SOME(parent));
      bt = balance(node);
    then bt;
  end match;
end exchangeRight;

protected function rotateLeft "help function to balance"
input AvlTree node;
output AvlTree outNode "updated node";
algorithm
  outNode := exchangeLeft(getOption(rightNode(node)),node);
end rotateLeft;

protected function getOption "Retrieve the value of an option"
  replaceable type T subtypeof Any;
  input Option<T> opt;
  output T val;
algorithm
  val := match(opt)
    case(SOME(val)) then val;
  end match;
end getOption;

protected function rotateRight "help function to balance"
input AvlTree node;
output AvlTree outNode "updated node";
algorithm
  outNode := exchangeRight(getOption(leftNode(node)),node);
end rotateRight;

protected function differenceInHeight "help function to balance, calculates the difference in height
between left and right child"
  input AvlTree node;
  output Integer diff;
algorithm
  diff := match (node)
    local
      Integer lh,rh;
      Option<AvlTree> l,r;
    case(FCore.CAVLTREENODE(left=l,right=r))
      equation
        lh = getHeight(l);
        rh = getHeight(r);
      then lh - rh;
  end match;
end differenceInHeight;

public function avlTreeGet
  "Get a value from the binary tree given a key."
  input AvlTree inAvlTree;
  input AvlKey inKey;
  output AvlValue outValue;
algorithm
  outValue := match (inAvlTree,inKey)
    local
      AvlKey rkey,key;
    case (FCore.CAVLTREENODE(value = SOME(FCore.CAVLTREEVALUE(key=rkey))),key)
      then avlTreeGet2(inAvlTree,stringCompare(key,rkey),key);
  end match;
end avlTreeGet;

protected function avlTreeGet2
  "Get a value from the binary tree given a key."
  input AvlTree inAvlTree;
  input Integer keyComp "0=get value from current node, 1=search right subtree, -1=search left subtree";
  input AvlKey inKey;
  output AvlValue outValue;
algorithm
  outValue := match (inAvlTree,keyComp,inKey)
    local
      AvlKey key;
      AvlValue rval;
      AvlTree left,right;

    // hash func Search to the right
    case (FCore.CAVLTREENODE(value = SOME(FCore.CAVLTREEVALUE(value=rval))),0,key)
      then rval;

    // search to the right
    case (FCore.CAVLTREENODE(right = SOME(right)),1,key)
      then avlTreeGet(right, key);

    // search to the left
    case (FCore.CAVLTREENODE(left = SOME(left)),-1,key)
      then avlTreeGet(left, key);
  end match;
end avlTreeGet2;

protected function getOptionStr "Retrieve the string from a string option.
  If NONE() return empty string."
  input Option<Type_a> inTypeAOption;
  input FuncTypeType_aToString inFuncTypeTypeAToString;
  output String outString;
  replaceable type Type_a subtypeof Any;
  partial function FuncTypeType_aToString
    input Type_a inTypeA;
    output String outString;
  end FuncTypeType_aToString;
algorithm
  outString:=
  match (inTypeAOption,inFuncTypeTypeAToString)
    local
      String str;
      Type_a a;
      FuncTypeType_aToString r;
    case (SOME(a),r)
      equation
        str = r(a);
      then
        str;
    case (NONE(),_) then "";
  end match;
end getOptionStr;

protected function printAvlTreeStr "
  Prints the avl tree to a string"
  input AvlTree inAvlTree;
  output String outString;
algorithm
  outString:=
  match (inAvlTree)
    local
      AvlKey rkey;
      String s2,s3,res;
      AvlValue rval;
      Option<AvlTree> l,r;
      Integer h;

    case (FCore.CAVLTREENODE(value = SOME(FCore.CAVLTREEVALUE(rkey,rval)),height = h,left = l,right = r))
      equation
        s2 = getOptionStr(l, printAvlTreeStr);
        s3 = getOptionStr(r, printAvlTreeStr);
        res = "\n" +& valueStr(rval) +& ",  " +& Util.if_(stringEq(s2, ""), "", s2 +& ", ") +& s3;
      then
        res;
    case (FCore.CAVLTREENODE(value = NONE(),left = l,right = r))
      equation
        s2 = getOptionStr(l, printAvlTreeStr);
        s3 = getOptionStr(r, printAvlTreeStr);
        res = Util.if_(stringEq(s2, ""), "", s2 +& ", ") +& s3;
      then
        res;
  end match;
end printAvlTreeStr;

protected function computeHeight "compute the heigth of the AvlTree and store in the node info"
  input AvlTree bt;
  output AvlTree outBt;
algorithm
  outBt := match(bt)
    local
      Option<AvlTree> l,r;
      Option<AvlTreeValue> v;
      Integer hl,hr,height;
    case(FCore.CAVLTREENODE(value=v as SOME(_),left=l,right=r))
      equation
        hl = getHeight(l);
        hr = getHeight(r);
        height = intMax(hl,hr) + 1;
      then FCore.CAVLTREENODE(v,height,l,r);
  end match;
end computeHeight;

protected function getHeight "Retrieve the height of a node"
  input Option<AvlTree> bt;
  output Integer height;
algorithm
  height := match (bt)
    case(NONE()) then 0;
    case(SOME(FCore.CAVLTREENODE(height = height))) then height;
  end match;
end getHeight;

public function printAvlTreeStrPP
  input AvlTree inTree;
  output String outString;
algorithm
  outString := printAvlTreeStrPP2(SOME(inTree), "");
end printAvlTreeStrPP;

protected function printAvlTreeStrPP2
  input Option<AvlTree> inTree;
  input String inIndent;
  output String outString;
algorithm
  outString := match(inTree, inIndent)
    local
      AvlKey rkey;
      Option<AvlTree> l, r;
      String s1, s2, res, indent;

    case (NONE(), _) then "";

    case (SOME(FCore.CAVLTREENODE(value = SOME(FCore.CAVLTREEVALUE(key = rkey)), left = l, right = r)), _)
      equation
        indent = inIndent +& "  ";
        s1 = printAvlTreeStrPP2(l, indent);
        s2 = printAvlTreeStrPP2(r, indent);
        res = "\n" +& inIndent +& rkey +& s1 +& s2;
      then
        res;

    case (SOME(FCore.CAVLTREENODE(value = NONE(), left = l, right = r)), _)
      equation
        indent = inIndent +& "  ";
        s1 = printAvlTreeStrPP2(l, indent);
        s2 = printAvlTreeStrPP2(r, indent);
        res = "\n" +& s1 +& s2;
      then
        res;
  end match;
end printAvlTreeStrPP2;

public function avlTreeReplace
  "Replaces the value of an already existing node in the tree with a new value."
  input AvlTree inAvlTree;
  input AvlKey inKey;
  input AvlValue inValue;
  output AvlTree outAvlTree;
algorithm
  outAvlTree := match(inAvlTree, inKey, inValue)
    local
      AvlKey key, rkey;
      AvlValue value;

    case (FCore.CAVLTREENODE(value = SOME(FCore.CAVLTREEVALUE(key = rkey))), key, value)
      then avlTreeReplace2(inAvlTree, stringCompare(key, rkey), key, value);

    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR, {"Env.avlTreeReplace failed"});
      then fail();

  end match;
end avlTreeReplace;

protected function avlTreeReplace2
  "Helper function to avlTreeReplace."
  input AvlTree inAvlTree;
  input Integer inKeyComp;
  input AvlKey inKey;
  input AvlValue inValue;
  output AvlTree outAvlTree;
algorithm
  outAvlTree := match(inAvlTree, inKeyComp, inKey, inValue)
    local
      AvlKey key;
      AvlValue value;
      Option<AvlTree> left, right;
      Integer h;
      AvlTree t;
      Option<AvlTreeValue> oval;

    // Replace this node.
    case (FCore.CAVLTREENODE(value = SOME(_), height = h, left = left, right = right),
        0, key, value)
      then FCore.CAVLTREENODE(SOME(FCore.CAVLTREEVALUE(key, value)), h, left, right);

    // Insert into right subtree.
    case (FCore.CAVLTREENODE(value = oval, height = h, left = left, right = right),
        1, key, value)
      equation
        t = createEmptyAvlIfNone(right);
        t = avlTreeReplace(t, key, value);
      then
        FCore.CAVLTREENODE(oval, h, left, SOME(t));

    // Insert into left subtree.
    case (FCore.CAVLTREENODE(value = oval, height = h, left = left, right = right),
        -1, key, value)
      equation
        t = createEmptyAvlIfNone(left);
        t = avlTreeReplace(t, key, value);
      then
        FCore.CAVLTREENODE(oval, h, SOME(t), right);
  end match;
end avlTreeReplace2;

public function getAvlTreeValues
  input list<Option<AvlTree>> tree;
  input list<AvlTreeValue> acc;
  output list<AvlTreeValue> res;
algorithm
  res := match (tree,acc)
    local
      Option<AvlTreeValue> value;
      Option<AvlTree> left,right;
      list<Option<AvlTree>> rest;
    case ({},_) then acc;
    case (SOME(FCore.CAVLTREENODE(value=value,left=left,right=right))::rest,_)
      then getAvlTreeValues(left::right::rest,List.consOption(value,acc));
    case (NONE()::rest,_) then getAvlTreeValues(rest,acc);
  end match;
end getAvlTreeValues;

public function getAvlValue
  input AvlTreeValue inValue;
  output AvlValue res;
algorithm
  res := match (inValue)
    case FCore.CAVLTREEVALUE(value = res) then res;
  end match;
end getAvlValue;

public function getAvlValues
  input AvlTree inAvlTree;
  output list<AvlValue> outAvlValues;
protected
  list<AvlTreeValue> avlTreeValues;
algorithm
  avlTreeValues := getAvlTreeValues({SOME(inAvlTree)}, {});
  outAvlValues := List.map(avlTreeValues, getAvlValue); 
end getAvlValues;

// ************************ END AVL Tree implementation ***************************
// ************************ END AVL Tree implementation ***************************
// ************************ END AVL Tree implementation ***************************
// ************************ END AVL Tree implementation ***************************

end FNode;