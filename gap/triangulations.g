#############################################################################
##
#W triangulations.g                                         Laurent Bartholdi
##
#H   @(#)$Id$
##
#Y Copyright (C) 2011, Laurent Bartholdi
##
#############################################################################
##
##  Triangulations of spheres
##
#############################################################################

UTIME@ := function()
    local v;
    v := ValueGlobal("IO_gettimeofday")();
    return v.tv_sec+1.e-6_l*v.tv_usec;
end;

LASTTIME@ := 0; TIMES@ := []; MARKTIME@ := function(n) # crude time profiling
    local t;
    t := UTIME@();
    if n=0 then LASTTIME@ := t; return; fi;
    if not IsBound(TIMES@[n]) then TIMES@[n] := 0.0_l; fi;
    TIMES@[n] := TIMES@[n]+t - LASTTIME@;
    LASTTIME@ := t;
end;

BindGlobal("MAKEP1EPS@", function()
    if ValueOption("precision")<>fail then
        @.p1eps := ValueOption("precision");
    else
        @.p1eps := Sqrt(@.reps); # error allowed on P1Map
    fi;
    @.maxratio := 100*@.ro; # maximum ratio, in triangulation, of circumradius to edge length
    if ValueOption("obstruction")<>fail then
        @.obst := ValueOption("obstruction");
    else
        @.obst := 10^-2*@.ro; # points that close are suspected to form an obstruction
    fi;
    @.fast := 10^-1*@.ro; # if spider moved that little, just wiggle it
    @.ratprec := @.reps^(3/4); # quality to achieve in rational fct.
end);

InstallMethod(SPIDERRELATOR@, [IsMarkedSphere],
        spider->Product(GeneratorsOfGroup(spider!.model){spider!.ordering}));

InstallMethod(NFFUNCTION@, [IsMarkedSphere],
        spider->NFFUNCTION@(spider!.model, SPIDERRELATOR@(spider)));


BindGlobal("POSITIONID@", function(l,x)
    return PositionProperty(l,y->IsIdenticalObj(x,y));
end);

BindGlobal("INID@", function(x,l)
    return ForAny(l,y->IsIdenticalObj(x,y));
end);

InstallMethod(ViewString, "(FR) for a triangulation",
        [IsSphereTriangulation],
        t->CONCAT@("<triangulation with ",Length(t!.v)," vertices, ",Length(t!.e)," edges and ",Length(t!.f)," faces>"));

InstallMethod(String, "(FR) for a triangulation",
        [IsSphereTriangulation],
        t->"DelaunayTriangulation(...)");

InstallMethod(DisplayString, "(FR) for a triangulation",
        [IsSphereTriangulation],
        function(t)
    local i, j, s;
    s := "   vertex | position                                 | neighbours\n";
    Append(s,"----------+------------------------------------------+-----------------\n");
    for i in t!.v do
        Append(s,String(CONCAT@("Vertex ",i.index),9));
        Append(s," | ");
        Append(s,String(i.pos,-40));
        Append(s," |");
        for j in i.n do APPEND@(s," ",j.index); od;
        Append(s,"\n");
    od;
    Append(s,"----------+------------------------------------------+-----------------\n");
    Append(s,"     edge | position                                 |frm to lt rt rev\n");
    Append(s,"----------+------------------------------------------+-----------------\n");
    for i in t!.e do
        Append(s,String(CONCAT@("Edge ",i.index),9));
        Append(s," | ");
        Append(s,String(i.pos,-40));
        Append(s," |");
        for j in [i.from,i.to,i.left,i.right,i.reverse] do Append(s,String(j.index,3)); od;
        Append(s,"\n");
    od;
    Append(s,"----------+------------------------------------------+----------v-----------\n");
    Append(s,"     face | position                                 | radius   | neighbours\n");
    Append(s,"----------+------------------------------------------+----------+-----------\n");
    for i in t!.f do
        Append(s,String(CONCAT@("Face ",i.index),9));
        Append(s," | ");
        Append(s,String(i.pos,-40));
        Append(s," |");
        Append(s,String(i.radius,-9));
        Append(s," |");
        for j in i.n do Append(s," "); Append(s,String(j.index)); od;
        Append(s,"\n");
    od;
    Append(s,"----------+------------------------------------------+----------+-----------\n");
    return s;
end);
INSTALLPRINTERS@(IsSphereTriangulation);

BindGlobal("LOCATE@", function(t,f0,p)
    # for an initial face f0 and a P1Point p
    # f0 is allowed to be <fail>, in which case the first face is chosen
    # returns either [face,barycentric_coords],
    #             or [face,edge,edge_coord],
    #             or [face,edge_in,edge_out,vertex]
    local baryc, yc, i, seen;
    
    if f0=fail then f0 := t!.f[1]; fi;
    # bad, this can cost linear time, and not logarithmic.
    # we should use a "rho" method to detect loops
    seen := BlistList([1..Length(t!.f)],[]);
    repeat
        baryc := List(f0.n,e->P1Image(InverseP1Map(e.map),p));
        yc := List(baryc,SphereP1Y);
        if ForAll(yc,x->x>-@.reps) or seen[f0.index] then
            if seen[f0.index] then
                Info(InfoFR,1,"We're stuck in a loop; I'll exit, cross your fingers");
            fi;
            break;
        fi;
        i := Position(yc,Minimum(yc));
        seen[f0.index] := true;
        f0 := f0.n[i].right;
    until false;
    
    i := Filtered([1..3],i->AbsoluteValue(yc[i])<@.reps);
    if i=[] then # inside face
        return [f0,yc];
    elif Size(i)=1 then # on edge
        i := i[1];
        baryc := RealPart(P1Coordinate(baryc[i]));
        return [f0,f0.n[i],baryc];
    elif Size(i)=2 then # at vertex
        i := Intersection(i,1+i mod 3)[1];
        return [f0,f0.n[1+((1+i)mod 3)],f0.n[i],f0.n[i].from];
    else
        Error("There is probably a triangle with a flat angle. I'm stuck");
    fi;
end);

BindGlobal("EDGEMAP@",
        e->P1Path(e.from.pos,e.to.pos));

DeclareGlobalFunction("SWAPTEST@");
InstallGlobalFunction(SWAPTEST@, function(p,e)
    # p is opposite of edge e on face e.left. check if e should be swapped.
    local a, b, q, bp, pa, aq, qb, f, pqb, qpa;
    f := e.reverse;
    a := e.from;
    b := e.to;
    for pa in e.left.n do if IsIdenticalObj(pa.from,p) then break; fi; od;
    for bp in e.left.n do if IsIdenticalObj(bp.to,p) then break; fi; od;
    for aq in e.right.n do if IsIdenticalObj(aq.from,a) then break; fi; od;
    for qb in e.right.n do if IsIdenticalObj(qb.to,b) then break; fi; od;
    q := aq.to;
    if ImaginaryPart(P1XRatio(p.pos,q.pos,a.pos,b.pos))>@.rz then
        Remove(a.n,POSITIONID@(a.n,e));
        Remove(b.n,POSITIONID@(b.n,f));
        e.from := p; e.to := q;
        e.map := EDGEMAP@(e); e.len := P1Distance(p.pos,q.pos);
        f.from := q; f.to := p;
        f.map := EDGEMAP@(f); f.len := e.len;
        pqb := e.left; qpa := e.right;
        pa.left := qpa; pa.reverse.right := qpa;
        qb.left := pqb; qb.reverse.right := pqb;
        pqb.n := [e,qb,bp];
        qpa.n := [f,pa,aq];
        Add(p.n,e,POSITIONID@(p.n,pa)+1);
        Add(q.n,f,POSITIONID@(q.n,qb)+1);
        Unbind(pqb.radius); # make sure the radius gets recomputed
        Unbind(qpa.radius);
        if IsBound(e.gpelement) then
            pa.gpelement := e.gpelement^-1*pa.gpelement;
            pa.reverse.gpelement := pa.gpelement^-1;
            qb.gpelement := e.gpelement*qb.gpelement;
            qb.reverse.gpelement := qb.gpelement^-1;
        fi;
        SWAPTEST@(p,aq);
        SWAPTEST@(p,qb);
    fi;
end);

BindGlobal("CHECKTRIANGULATION@", function(t)
    local x;
    x := Filtered(t!.v,v->not ForAll(v.n,e->IsIdenticalObj(e.from,v)));
    if x<>[] then return [false,1]; fi;
    x := Filtered(t!.e,e->not INID@FR(e,e.from.n) or not INID@FR(e,e.left.n));
    if x<>[] then return [false,2]; fi;
    x := Filtered(t!.f,f->not ForAll(f.n,e->IsIdenticalObj(e.left,f)));
    if x<>[] then return [false,3]; fi;
    x := Filtered(t!.f,f->not IsIdenticalObj(LOCATE@(t,f,f.pos)[1],f));
    if x<>[] then return [false,4]; fi;
    return true;
end);

BindGlobal("ADDTOTRIANGULATION@", function(t,f,p)
    # adds point p, in face f, to triangulation t
    local nv, ne, nf, i, d;
    
    nv := rec(type := 'v', pos := p, n := [], index := Length(t!.v)+1, operations := t!.v[1].operations); Add(t!.v,nv);
    ne := [];
    nf := List([1..2],i->rec(type := 'f', index := Length(t!.f)+i, operations := t!.f[1].operations)); Append(t!.f,nf);
    nf[3] := f; Unbind(f.radius); # recycle record f
    for i in [1..3] do
        ne[i] := rec(type := 'e', from := nv, to := f.n[i].from, left := nf[i], right := nf[1+(i+1) mod 3], len := P1Distance(nv.pos,f.n[i].from.pos));
        ne[i+3] := rec(type := 'e', from := ne[i].to, to := nv, left := ne[i].right, right := nf[i], reverse := ne[i], len := ne[i].len);
        ne[i].reverse := ne[i+3];
    od;
    for i in [1..6] do
        ne[i].map := EDGEMAP@(ne[i]);
        ne[i].index := Length(t!.e)+i;
        ne[i].operations := t!.e[1].operations;
        if IsBound(t!.e[1].gpelement) then
            ne[i].gpelement := One(t!.e[1].gpelement);
        fi;
    od;
    Append(t!.e,ne);
    d := f.n; # f.n will get overwritten below
    for i in [1..3] do
        nf[i].n := [ne[i],d[i],ne[4+i mod 3]];
        f.n[i].left := nf[i];
        f.n[i].reverse.right := nf[i];
        Add(d[i].from.n,ne[i+3],POSITIONID@(d[i].from.n,d[i])+1);
    od;
    nv.n := ne{[1..3]};
    
    # flip diagonals if needed, to preserve Delaunay condition
    for i in d do SWAPTEST@(nv,i); od;
end);

# these should all be objects, in clean implementation
BindGlobal("ISVERTEX@", r->r.type='v');
BindGlobal("ISEDGE@", r->r.type='e');
BindGlobal("ISFACE@", r->r.type='f');

InstallMethod(DelaunayTriangulation, "(FR) for a list of points",
        [IsList], points->DelaunayTriangulation(points,@.rinf));

InstallMethod(DelaunayTriangulation, "(FR) for a list of points and a quality",
        [IsList, IsFloat],
        function(points,quality)
    local t, i, order, n, im, p, d, idle, print;
    
    while not ForAll(points,IsP1Point) do
        Error("DelaunayTriangution: argument should be a list of points on P1");
    od;
    
    print := rec(ViewObj := function(x)
        if ISVERTEX@(x) then
            Print("<vertex ",x.index,List(x.n,e->e.index),">");
        elif ISEDGE@(x) then
            Print("<edge ",x.index,List([x.from,x.to],v->v.index),">");
        else
            Print("<face ",x.index,List(x.n,e->e.index),">");
        fi;
    end, PrintObj := ~.ViewObj);

    n := Length(points);
    if n=0 then points := [P1infinity]; n := 1; fi;    
    d := List(points,x->P1Distance(points[n],x));
    order := [n]; # points[order[1]] is last point, presumably infinity
    im := List(d,v->AbsoluteValue(v-@.pi/2));
    i := POSITIONID@(im,MinimumList(im));

    if im[i]>=@.pi/6 then # all points are more or less aligned to points[order[1]]
        points := ShallowCopy(points);
        i := POSITIONID@(d,MaximumList(d));
        if d[i]<@.pi/2 then # actually all points are close to points[order[1]]
            Add(points,P1Antipode(points[n]));
            Add(order,Length(points));
        else
            Add(order,i);
        fi;
        for p in [P1one,P1Point(@.i),P1Point(-@.o),P1Point(-@.i)] do
            t := MoebiusMap(points[n],points[order[2]]);
            Add(points,P1Image(t,p));
            Add(order,Length(points));
        od;
    else # points[i] is roughly at 90 degrees from points[n]
        t := MoebiusMap(points[n],points[i],P1Antipode(points[n]));
        # so t(0)=points[n], t(1)=points[i]. Try to find points close to t^-1(infty,-1,i,-i).
        i := InverseP1Map(t); im := List(points,x->P1Image(i,x));
        for p in [P1infinity,P1one,P1Point(@.i),P1Point(-@.o),P1Point(-@.i)] do
            d := List(im,x->P1Distance(x,p));
            i := POSITIONID@(d,MinimumList(d));
            if d[i]>=@.pi/6 then
                if Length(points)=n then points := ShallowCopy(points); fi;
                Add(points,P1Image(t,p));
                Add(order,Length(points));
            else
                Add(order,i);
            fi;
        od;
    fi;
    Assert(1,IsDuplicateFreeList(order),"DelaunayTriangulation couldn't create octahedron");

    Append(order,Difference([1..n],order)); # so now order[1..6] is roughly an octahedron:
    # points{order{[1..6]}} = [0,infty,1,i,-1,-i]

    # create the octahedron
    t := rec(v := List([1..6],i->rec(type := 'v', pos := points[order[i]], n := [], index := order[i], operations := print)),
             e := List([1..24],i->rec(type := 'e', index := i, operations := print)),
             f := List([1..8],i->rec(type := 'f', index := i, operations := print)));
    for i in [1..2] do t.v[i].n := t.e{8*i-8+[1,3,5,7]}; od;
    for i in [1..4] do t.v[i+2].n := t.e{[2*i,24-2*((5-i) mod 4),18-2*i,15+2*i]}; od;
    for i in [1..4] do t.f[i].n := t.e{[15+2*i,2+2*(i mod 4),2*i-1]}; od;
    for i in [1..4] do t.f[i+4].n := t.e{[16+2*i,18-2*i,15-2*(i mod 4)]}; od;
    for p in t.v do for i in p.n do i.from := p; od; od;
    for p in t.f do for i in p.n do i.left := p; od; od;
    for i in [1..24] do
        t.e[i].reverse := t.e[i-(-1)^i];
        t.e[i].to := t.e[i].reverse.from;
        t.e[i].right := t.e[i].reverse.left;
        t.e[i].map := EDGEMAP@(t.e[i]);
        t.e[i].len := P1Distance(t.e[i].from.pos,t.e[i].to.pos);
    od;

    # now add the other points
    for i in [7..Length(points)] do
        p := points[order[i]];
        im := LOCATE@(t,fail,points[order[i]]);
        while Length(im)=4 do # vertex
            Error("Two vertices coincide: ",p," and ",im[4]);
        od;
        ADDTOTRIANGULATION@(t,im[1],p);
        t.v[i].index := order[i];
    od;
    
    t.v{order} := ShallowCopy(t.v); # reorder the points as they were before
    
    repeat
        idle := true;
        for i in t.f do
            if IsBound(i.radius) then continue; fi;
            p := CallFuncList(P1Circumcentre,List(i.n,e->e.from.pos));
            i.centre := p[1];
            i.radius := p[2];
            p := i.radius / MinimumList(List(i.n,e->e.len));
            if p > quality then
                ADDTOTRIANGULATION@(t,i,i.centre);
                idle := false;
            fi;
        od;
    until idle;
    
    for i in [n+1..Length(t.v)] do # remember these are added vertices
        t.v[i].fake := true;
    od;
    for i in t.e do
        i.pos := P1Barycentre(i.from.pos,i.to.pos);
    od;
    for i in t.f do
        i.pos := P1Barycentre(List(i.n,x->x.from.pos));
    od;
    t := Objectify(TYPE_TRIANGULATION,t);
    return t;
end);

BindGlobal("COPYTRIANGULATION@", function(t,movement)
    # movement is either a list of new positions for the vertices
    # (in which case the vertices, edges etc. should be wiggled to
    # their new positions), or a Möbius transformation, or true.
    local r, i, j;
    r := rec(v := StructuralCopy(t!.v),
             e := [],
             f := []);
    for i in r.v do
        for j in i.n do r.e[j.index] := j; r.f[j.left.index] := j.left; od;
    od;
    if IsList(movement) then
        r.wiggled := @.rz;
        for i in [1..Length(r.v)] do
            if not IsBound(r.v[i].fake) then
                r.wiggled := r.wiggled + P1Distance(r.v[i].pos, movement[i]);
                r.v[i].pos := movement[i];
            fi;
        od;
        for i in r.e do
            i.pos := P1Barycentre(i.from.pos,i.to.pos);
            i.map := EDGEMAP@(i);
        od;
        for i in r.f do
            i.pos := P1Barycentre(List(i.n,e->e.to.pos));
        od;
    elif IsP1Map(movement) then
        for i in r.v do i.pos := P1Image(movement,i.pos); od;
        for i in r.e do i.pos := P1Image(movement,i.pos); i.map := movement*i.map; od;
        for i in r.f do i.pos := P1Image(movement,i.pos); od;
    fi;
    return Objectify(TYPE_TRIANGULATION, r);
end);

BindGlobal("CLOSESTFACES@", function(x)
    if ISFACE@(x) then
        return [x];
    elif ISEDGE@(x) then
        return [x.left,x.right];
    else
        return List(x.n,x->x.to.left);
    fi;
end);

BindGlobal("CLOSESTVERTICES@", function(x)
    if ISFACE@(x) then
        return List(x.n,x->x.to);
    elif ISEDGE@(x) then
        return [x.to,x.from];
    else
        return [x];
    fi;
end);

InstallMethod(LocateInTriangulation, "(FR) for a triangulation and point",
        [IsSphereTriangulation, IsP1Point],
        function(t,p)
    return LOCATE@(t,fail,p)[1];
end);

InstallMethod(LocateInTriangulation, "(FR) for a triangulation, face/edge/vertex and point",
        [IsSphereTriangulation, IsRecord, IsP1Point],
        function(t,s,p)
    if ISFACE@(s) then
        return LOCATE@(t,s,p)[1];
    elif ISEDGE@(s) then
        return LOCATE@(t,s.left,p)[1];
    else
        return LOCATE@(t,s.n[1].left,p)[1];
    fi;
end);

BindGlobal("INTERPOLATE_ARC@", function(l)
    # interpolate along points of l
    local r, i, p;
    r := ShallowCopy(l);
    i := 1;
    while i<Length(r) do
        if P1Distance(r[i],r[i+1])>@.pi/12 then
            Add(r,P1Barycentre(r[i],r[i+1]),i+1);
        else
            i := i+1;
        fi;
    od;
    return r;
end);

BindGlobal("PRINTPT@", function(f,p1p,sep,s)
    local p;
    p := sep*SphereP1(p1p);
    PrintTo(f, p[1], " ", p[2], " ", p[3], s, "\n");
end);

BindGlobal("PRINTARC@", function(f,a,col,sep)
    local j;
    a := INTERPOLATE_ARC@(a);
    PrintTo(f, "ARC ",Length(a)," ",String(col[1])," ",String(col[2])," ",String(col[3]),"\n");
    for j in a do
        PRINTPT@(f, j, sep, "");
    od;
end);

BindGlobal("PRINTPOINTS@", function(f,t,extrapt)
    local i, x, n, arcs;
    
    arcs := ValueOption("noarcs")=fail;
    
    if arcs then
        n := Length(t!.v)+Length(t!.f);
    else
        n := Number(t!.v,v->not IsBound(v.fake));
    fi;
    PrintTo(f, "POINTS ",n+Length(extrapt),"\n");
    for i in t!.v do
        if IsBound(i.fake) and arcs then
            PRINTPT@(f, i.pos, @.ro, " 0.5");
        elif not IsBound(i.fake) then
            x := ViewString(CleanedP1Point(i.pos,@.p1eps));
            RemoveCharacters(x,"<>");
            PRINTPT@(f, i.pos, @.ro, Concatenation(" 2.0 ",x));
        fi;
    od;
    if arcs then
        for i in t!.f do PRINTPT@(f, i.pos, @.ro, " 1.0"); od;
    fi;
    for i in extrapt do PRINTPT@(f, i.pos, @.ro, " 0.5"); od;
end);

InstallMethod(Draw, "(FR) for a triangulation",
        [IsSphereTriangulation],
        function(t)
    local s, f, i;
    s := ""; f := OUTPUTTEXTSTRING@(s);
    
    if ValueOption("upper")<>fail then
        PrintTo(f,"UPPER");
    fi;
    if ValueOption("lower")<>fail then
        PrintTo(f,"LOWER");
    fi;
    
    PRINTPOINTS@(f,t,[]);
    
    if ValueOption("noarcs")<>fail then
        PrintTo(f, "ARCS 0\n");
    else
        PrintTo(f, "ARCS ", Length(t!.e),"\n");
        for i in t!.e do if i.index > i.reverse.index then
            PRINTARC@(f, [i.from.pos,i.pos,i.to.pos], [255,0,255], @.ro);
            PRINTARC@(f, [i.left.pos,i.pos,i.right.pos], [0,255,255], @.ro);
        fi; od;
    fi;
    
    Info(InfoFR,3,"calling javaplot with:\n",s);
    JAVAPLOT@(InputTextString(s));
end);
##############################################################################

##############################################################################
##
#M  MarkedSpheres
##
InstallMethod(ViewString, "(FR) for a point in Teichmuller space",
        [IsMarkedSphere],
        s->Concatenation("<marked sphere on ",ViewString(s!.cut)," marked by ",String(s!.marking),">"));

InstallMethod(DisplayString, "(FR) for a point in Teichmuller space",
        [IsMarkedSphere],
        s->CONCAT@(DisplayString(s!.cut),"Spanning tree on edges ",List(s!.treeedge,r->r.index)," costing ",s!.treecost,"\nMarking ",s!.marking,"\n"));

InstallMethod(String, "(FR) for a point in Teichmuller space",
        [IsMarkedSphere],
        s->Concatenation("Spider(",ViewString(s!.cut),")"));

INSTALLPRINTERS@(IsMarkedSphere);

BindGlobal("STRINGCOMPLEX@",
    z->CONCAT@(RealPart(z)," ",ImaginaryPart(z)));

InstallMethod(Draw, "(FR) for a point in Teichmuller space",
        [IsMarkedSphere],
        function(spider)
    local a, i, j, k, s, f, t, points, arcs;
    s := ""; f := OUTPUTTEXTSTRING@(s);
    
    if ValueOption("upper")<>fail then
        PrintTo(f,"UPPER\n");
    fi;
    if ValueOption("lower")<>fail then
        PrintTo(f,"LOWER\n");
    fi;
    if IsBound(spider!.map) and ValueOption("julia")<>fail then
        t := DegreeOfP1Map(spider!.map);
        PrintTo(f,"FUNCTION");
        a := List(CoefficientsOfP1Map(spider!.map),ShallowCopy);
        for i in [1..t+1] do PrintTo(f," ",STRINGCOMPLEX@(a[1][i])); od;
        for i in [1..t+1] do PrintTo(f," ",STRINGCOMPLEX@(a[2][i])); od;
        PrintTo(f,"\nCYCLES");
        if IsBound(spider!.cycle) then
            for i in spider!.cycle do
                if i[1]=P1infinity then
                    PrintTo(f," Infinity any");
                else
                    PrintTo(f," ",STRINGCOMPLEX@(P1Coordinate(i[1])));
                fi;
                PrintTo(f," ",i[2]," ",i[3]);
            od;
        fi;
        t := ValueOption("julia");
        if IsList(t) then # size, maxiter
            i := t[1]; j := t[1];
        elif IsPosInt(t) then
            i := t; j := 100;
        else
            i := 500; j := 100;
        fi;
        PrintTo(f,"\nIMAGE ",i," ",j,"\n");
    fi;
    
    if IsBound(spider!.points) then
        points := spider!.points;
    else
        points := [];
    fi;
    if IsBound(spider!.arcs) then
        arcs := spider!.arcs;
    else
        arcs := [];
    fi;
    
    t := spider!.cut;
    PRINTPOINTS@(f, t, points);

    if ValueOption("noarcs")<>fail then
        PrintTo(f, "ARCS 0\n");
    else
        PrintTo(f, "ARCS ", Length(t!.e)+Length(arcs),"\n");
        for i in t!.e do
            if i.from.index>i.to.index then # print only in 1 direction
                continue;
            fi;
            j := [128,64,64];
            k := [64,128,64];
            if not IsOne(i.gpelement) then
                j := [255,64,64];
            else
                k := [64,255,64];
            fi;
            PRINTARC@(f, [i.from.pos,i.pos,i.to.pos], j, Float(101/100));
            PRINTARC@(f, [i.left.pos,i.pos,i.right.pos], k, Float(102/100));
        od;
        for a in arcs do PRINTARC@(f, a[3], a[1], a[2]); od;
    fi;
    
    Info(InfoFR,3,"calling javaplot with:\n",s);
    JAVAPLOT@(InputTextString(s));
end);

BindGlobal("CHECKSPIDER@", function(s)
    return CHECKTRIANGULATION@(s!.cut) and IsOne(SPIDERRELATOR@(s)^s!.marking);
end);

BindGlobal("CHECKREC@", function(recur,order,reduce)
    local i, j, a, result, w;
    
    result := [[],[]];
    for i in [1..Length(recur[2][1])] do
        w := One(recur[1][1][1]);
        a := i;
        for j in order do
            w := w*recur[1][j][a];
            a := recur[2][j][a];
        od;
        Add(result[1],reduce(w));
        Add(result[2],a);
    od;
    return result[2]=[1..Length(recur[2][1])] and ForAll(result[1],IsOne);
end);

BindGlobal("TRIVIALSPIDER@", function(points)
    # constructs a spider with identity marking on <points>
    local n, f, r, g, edges, tree, cost, p, i, e;
    n := Length(points);
    f := FreeGroup(n-1);
    r := rec(model := f,                            # marking group
             cut := DelaunayTriangulation(points,@.maxratio), # triangulation
             group := f,                            # group on spanning tree
             marking := IdentityMapping(f),         # isomorphism between them
             intree := [],                          # if an edge is in the tree
             treeedge := []);                       # for each generator, a preferred edge with that label
    
    # construct a spanning tree
    edges := List(r!.cut!.e,e->[e.from.index,e.to.index]);
    cost := List(r!.cut!.e,e->e.len);
    tree := MINSPANTREE@(edges,cost);
    r.treecost := Remove(tree);
    tree := List(tree,p->First(r.cut!.v[p[1]].n,e->e.to.index=p[2]));
    SortParallel(cost{List(tree,e->e.index)},tree);
    
    # start by a free group on the edges of the tree
    # by convention, if the edge goes north, then the generator, with
    # positive orientation, goes from west to east.
    g := FreeGroup(Length(tree));
    p := PresentationFpGroup(g,0);
    TzOptions(p).protected := Length(tree);
    TzInitGeneratorImages(p);
    
    for i in r.cut!.e do i.gpelement := One(g); od;
    r.intree := ListWithIdenticalEntries(Length(edges),false);
    for i in [1..Length(tree)] do
        e := GeneratorsOfGroup(g)[i];
        tree[i].gpelement := e;
        tree[i].reverse.gpelement := e^-1;
        r.intree[tree[i].index] := true;
        r.intree[tree[i].reverse.index] := true;
    od;
    
    # add relators saying the cycle around a fake vertex is trivial
    for i in r!.cut!.v do
        if IsBound(i.fake) then
            AddRelator(p,Product(List(Reversed(i.n),e->e.gpelement)));
        fi;
    od;
    
    # eliminate useless generators, starting by the shortest
    for i in GeneratorsOfPresentation(p) do
        TzEliminate(p,i);
    od;
    for i in r.cut!.e do i.gpelement := One(f); od;
    for i in [1..Length(tree)] do
        e := MappedWord(TzImagesOldGens(p)[i],GeneratorsOfPresentation(p),GeneratorsOfGroup(f));
        tree[i].gpelement := e;
        tree[i].reverse.gpelement := e^-1;
    od;
    
    r.treeedge := List(TzPreImagesNewGens(p),w->tree[TietzeWordAbstractWord(w)[1]]);

    return Objectify(TYPE_SPIDER,r);
end);

BindGlobal("COPYSPIDER@", function(spider,movement)
    # movement is either a list of new positions for the vertices
    # (in which case the vertices, edges etc. should be wiggled to
    # their new positions), or a Möbius transformation, or true.
    local r;
    r := rec(model := spider!.model,
             cut := COPYTRIANGULATION@(spider!.cut,movement),
             group := spider!.group,
             marking := spider!.marking,
             treecost := spider!.treecost,
             intree := spider!.intree);
    r.treeedge := r.cut!.e{List(spider!.treeedge,e->e.index)};
    if IsBound(spider!.ordering) then
        r.ordering := spider!.ordering;
    fi;

    return Objectify(TYPE_SPIDER,r);
end);

InstallMethod(TREEBOUNDARY@, [IsMarkedSphere],
        function(spider)
    # return a list of edges traversed when one surrounds the tree with
    # it on our left. visit vertex n first.
    local i, e, edges, n;

    n := Length(VERTICES@(spider));
    e := First(spider!.cut!.e,e->spider!.intree[e.index] and e.from.index=n);
    edges := [];
    repeat
        Add(edges,e);
        i := POSITIONID@(e.to.n,e.reverse);
        repeat
            i := i+1;
            if i>Length(e.to.n) then i := 1; fi;
        until spider!.intree[e.to.n[i].index];
        e := e.to.n[i];
    until IsIdenticalObj(e,edges[1]);
    return edges;
end);

BindGlobal("IMGMARKING@", function(spider,model)
    # changes the marking group so that it's generated by lollipops
    # around punctures.
    # model is the group to be used for these lollipops; it has one generator
    # per non-fake vertex.
    # the command sets the fields "ordering" and "marking" in spider
    local e, image, ordering;

    spider!.model := model;
    ordering := [];
    image := [];

    for e in TREEBOUNDARY@(spider) do
        if not IsBound(e.from.fake) then
            if not IsBound(image[e.from.index]) then
                image[e.from.index] := One(spider!.group);
                Add(ordering,e.from.index);
            fi;
            image[e.from.index] := image[e.from.index] / e.gpelement;
        fi;
    od;
    while ordering[1]<>Length(ordering) do # force ordering[n]=n
        Add(ordering,Remove(ordering,1));
    od;
    spider!.ordering := Reversed(ordering);
    spider!.marking := GroupHomomorphismByImagesNC(model,spider!.group,GeneratorsOfGroup(model),image{[1..Length(GeneratorsOfGroup(model))]});
end);
##############################################################################

##############################################################################
##
#M  Function to IMG
##
BindGlobal("MATCHPOINTS@", function(ptA, ptB)
    # ptA is a list of n points; ptB[i] is a list of neighbours of ptA[i]
    # each ptB[i][j] is a sphere point
    # returns: a matching i|->j(i), [1..n]->[1..n] such that
    # ptA is at least 2x closer to ptB[i][j(i)] as to other neighbours;
    # or return fail if no such matching exists.
    local i, j, dists, perm;

    dists := [];
    for i in [1..Length(ptA)] do
        dists[i] := List(ptB[i],v->P1Distance(ptA[i],v));
    od;
    perm := List(dists, l->Position(l,Minimum(l)));

    for i in [1..Length(dists)] do
        for j in [1..Length(dists[i])] do
            if j<>perm[i] and dists[i][j]<dists[i][perm[i]]*2 then
                return fail;
            fi;
        od;
    od;
    return perm;
end);

BindGlobal("ESSDISJOINT@", function(ratmap,p0,p1,domain)
    # return true if ratmap(P1Path(p0,p1)) is essentially disjoint
    # from domain's boundary
    local e, tu, delta, d;
    
    d := P1Distance(p0,p1);
    if d<@.p1eps then return true; fi;
    
    delta := P1Path(p0,p1);
    for e in domain.n do
MARKTIME@(1);
        tu := P1INTERSECT@(e.map,ratmap,delta);
MARKTIME@(2);
        for tu in tu do
            if d*(@.ro/2-AbsoluteValue(@.ro/2-tu[2])) > @.p1eps then
                return false;
            fi;
        od;
    od;
    return true;
end);

BindGlobal("LIFTARC@", function(spider,ratmap,from,to,gamma,downcell)
    # <gamma> is an arc in the range, contained in face <downcell>, which we
    # want to lift through <ratmap>.
    # <from> and <to> are described in LIFTEDGE@, as is the return value
    local curtime, nexttime, curface, curpos, curelt, curbdry, curedge,
          lift, lifts, xings, candidates,
          toface, e, f, i, c,
          choosebysubdivision, getcandidates, getbdry, getxings;

    choosebysubdivision := function(p0,t0,t1,candidates,upbdry)
    # candidates is a list of records containing in particular a field pos.
    # returns the one such that gamma[t0,t1] (which stays in downcell)
    # lifts to a path from p0 to candidate.pos and staying in upcell.
    # works by subdividing the time interval.
        local c, d, l, i, p, subdiv;
    
        subdiv := [rec(t := t0, pos := p0), rec(t := t1)];
        i := 2;
        while i <= Length(subdiv) do
            if not IsBound(subdiv[i].lifts) then
                subdiv[i].lifts := [];
                for p in P1PreImages(ratmap,P1Image(gamma,P1Point(subdiv[i].t))) do
                    if ForAll(upbdry,e->SphereP1Y(P1Image(InverseP1Map(e.map),p))>-@.reps) then
                        Add(subdiv[i].lifts,p);
                    fi;
                od;
            fi;
            p := subdiv[i].lifts;
            l := Length(p);
            if l=0 then
                Error("LIFTARC: I can't analytically continue, no candidate");
            elif l>1 then # many choices, find good one(s)
                p := Filtered(p,p->ESSDISJOINT@(ratmap,subdiv[i-1].pos,p,downcell));
                l := Length(p);
                if l>1 then
                    Error("LIFTARC: I can't analytically continue, too many candidates");
                elif l=0 then  # subdivide
                    Add(subdiv,rec(t := (subdiv[i-1].t+subdiv[i].t)/2),i);
                    continue;
                fi;
            fi;
            p := p[1];
            subdiv[i].pos := p;
            i := i+1;
        od;
        
        # now find closest candidate to point p.
        l := 2*@.pi; # bigger than maximal distance between P1 points
        for i in candidates do
            d := P1Distance(i.pos,p);
            if d<l then l := d; c := i; fi;
        od;
        return c;
    end;
    
    # compute a sequence of edges surrounding our current position
    getbdry := function()
        local e;
        
        if curedge<>fail then # we're parallel to an edge, i.e.
            curbdry := [];
            for e in curface.n do
                if not IsIdenticalObj(e,curedge.reverse) then
                    Add(curbdry,e);
                fi;
            od;
            for e in curedge.left.n do
                if not IsIdenticalObj(e,curedge) then
                    Add(curbdry,e);
                fi;
            od;
        else
            curbdry := curface.n;
        fi;
    end;
    
    # compute edge intersections on neighbours of current cell
    getxings := function()
        local e, l, r, i, tu;
        
        for e in curface.n do
            if not IsBound(xings[e.index]) then
                # get list of [t,u,d,p,q] such that gamma(t)=delta(u)=p,
                # e.map(u)=q, d=Im(gamma^-1*delta)'(u)
MARKTIME@(1);
                tu := P1INTERSECT@(gamma,ratmap,e.map);
MARKTIME@(2);
                # in increasing order along the edge
                Sort(tu,function(x,y) return x[2]<y[2]; end);
                l := []; r := []; i := 1;
                for tu in tu do
                    Add(l, rec(t := tu[1], u := tu[2], d := tu[3], gammapos := tu[4], pos := tu[5], e := e));
                    Add(r, rec(t := tu[1], u := (@.ro-tu[2])/(@.ro+tu[2]), d := -tu[3], gammapos := tu[4], pos := tu[5], e := e.reverse));
                    l[i].reverse := r[i];
                    r[i].reverse := l[i];
                    i := i+1;
                od;
                xings[e.index] := l;
                xings[e.reverse.index] := Reversed(r);
            fi;
        od;
    end;
    
    # out of the xings, find candidates:
    # - all endpoints of paths (in list "to")
    # - among edge crossings, only those at time >= curtime
    # - if we're parallel to an edge, all on that edge
    # - for the other ("boundary") crossings, only those pointing
    #   outward, and separated by (algebraically) >= #to and <= #from
    #   on the current face(s).
    getcandidates := function()
        local c, e;
        
        if IsBound(toface[curface.index]) then
            candidates := ShallowCopy(toface[curface.index]);
            nexttime := @.ro;
        else
            candidates := [];
            nexttime := 2*@.ro; # out of the way
        fi;
        
        if curedge<>fail then # we're parallel to an edge, i.e.
            # inside a lozenge. take its boundary.
            for c in xings[curedge.index] do
                if c.t > curtime then
                    if c.t < nexttime then nexttime := c.t; fi;
                    Add(candidates,c);
                fi;
            od;
        fi;
    
        for e in curbdry do
            for c in xings[e.index] do
                if c.t > curtime and c.d >= 0 then
                    if c.t < nexttime then nexttime := c.t; fi;
                    Add(candidates,c);
                fi;
            od;
        od;
    end;
    
    # the results will go there
    lifts := [];

    # xings[edge.index] are the (left-to-right) crossings of gamma with f(edge)
    xings := [];
    
    # toface is a list indexed by faces, containing starts and ends of lifts
    toface := [];
    for f in to do
        if not IsBound(toface[f.cell.index]) then toface[f.cell.index] := []; fi;
        Add(toface[f.cell.index],f);
    od;

    for lift in from do
        curface := lift.cell;
        curedge := fail; # will keep track of edge to which we're parallel
        curpos := lift.pos;
        curelt := lift.elt;
        curtime := -@.p1eps; # just in case we're on an edge or vertex

        repeat
            getbdry();
            getxings();
            getcandidates();
            
            c := First(candidates,c->ESSDISJOINT@(ratmap,curpos,c.pos,downcell));
            if candidates=[] then # our last chance is a "to" on the other side
                lift := fail;
                for e in curface.n do if IsBound(toface[e.right.index]) then
                    for c in toface[e.right.index] do
                        if ESSDISJOINT@(ratmap,curpos,c.pos,downcell) then
                            curelt := curelt * e.gpelement;
                            curface := e.right;
                            lift := c;
                            break;
                        fi;
                    od;
                    if lift<>fail then break; fi;
                fi; od;
            elif c=fail then                
                c := [];
                for i in candidates do
                   # if (nexttime=@.ro and not IsBound(i.t)) or i.t=nexttime then
		   if (nexttime = @FR.ro and  not IsBound( i.t )) or ( IsBound( i.t ) and  i.t = nexttime  ) then
                        Add(c,i);
                    fi;
                od;
                c := choosebysubdivision(curpos,curtime,nexttime,c,curbdry);
                if not IsBound(c.e) and not IsBound(c.cell) then # got a new point in curface
                    curpos := c.pos;
                    curtime := nexttime;
                    continue;
                fi;
            fi;
            
            if IsBound(c.cell) then # "to" cell: done!
                lift := ShallowCopy(Remove(toface[curface.index],POSITIONID@(toface[curface.index],c)));
                lift.elt := curelt;
                break;
            fi;
            
            # if we're parallel to an edge, maybe move back to the previous cell
            if not IsIdenticalObj(c.e.left,curface) then
                Error("This code is probably not necessary @@");
                curelt := curelt / c.e.gpelement;
            fi;
            
            curface := c.e.right;
            if c.d=0 then curedge := c.e; else curedge := fail; fi;
            curelt := curelt * c.e.gpelement;
            curtime := c.t;
            # if at a vertex, allow time to go back a little, in case the
            # edges don't really match
            if c.u < @.p1eps or c.u > @.ro-@.p1eps then
                curtime := curtime - 10*@.reps;
            fi;
            c.t := -@.ro; # mark xing, and its reverse, as unusable
            c.reverse.t := -@.ro;
        until false;
        Add(lifts,lift);
    od;
    return lifts;
end);

BindGlobal("LIFTEDGE@", function(spider,ratmap,from,to,edge)
    # lifts the arc perpendicular to <edge> through <ratmap>.
    # <from> is a list of rec(pos := <p1point>, cell := <face>,
    #     elt := <gpelement>), such that the <p1point> are the
    #     preimages of edge.left.pos.
    # <to> is a lift of rec(pos := <p1point>, cell := <face>), one per
    #     preimage of e.right.pos.
    # returns list <lifts> of length Degree(ratmap), where
    #     <lifts>[i] is a rec(pos := <p1point>, cell := <face>,
    #     elt := <gpelement>); this is a reordering of <to>,
    #     such that from[i] continues to to[i], and
    #     to[i].elt = from[i].elt * (product of edges crossed along the lift)
    local mid;
    
    Info(InfoFR,3,"Lifting edge ",edge);

    mid := List(P1PreImages(ratmap,edge.pos),y->rec(pos := y, cell := LOCATE@(spider!.cut,fail,y)[1]));
    
    mid := LIFTARC@(spider,ratmap,from,mid,P1Path(edge.left.pos,edge.pos),edge.left);
    return LIFTARC@(spider,ratmap,mid,to,P1Path(edge.pos,edge.right.pos),edge.right);
end);

BindGlobal("LIFTSPIDER@", function(target,src,ratmap,poly)
    # lifts all dual arcs in <src> through <ratmap>; rounds their endpoints
    # to faces of <target>; and rewrites the generators of <src> as words
    # in <target>'s group. <base> is a preferred starting face of <src>.
    # returns [face,edge] where:
    # face is a list of length Degree(ratmap), and contains lifts of faces,
    # indexed by the faces of <src>
    # face[i][j] is rec(pos, targetface, targetgpelt)
    local face, f, e, i, j, todo, lifts, perm, state, p, s, base, idle;
    
    # first lift all face centres, and choose a face containing the lift
    face := List(src!.cut!.f,x->List(P1PreImages(ratmap,x.pos),y->rec(pos := y, cell := LOCATE@(target!.cut,fail,y)[1])));
    
    # and choose a base point
    if poly then
        base := src!.cut!.v[Length(GeneratorsOfGroup(src!.group))].n[1].left; # some face touching infinity
    else
        base := src!.cut!.f[1];
    fi;
    for f in face[base.index] do
        f.elt := One(target!.group);
    od;
    
    # lift edges in the dual tree. If src!.cut!.f[i] lifts to points
    # in target!.cut!.f[j_1]...target!.cut!.f[j_d], then face[i][k], for k=1..d,
    # is a record (cell=j_k, elt=the word obtained by lifting the geodesic
    # from the basepoint to j_i, pos=exact position of the endpoint).
    todo := NewFIFO([base]);
    for f in todo do
        for e in f.n do
            # face[index] is a list of rec(pos := <position in P1>,
            #    cell := <cell in target>, and maybe elt := <group element>).
            # if elt is not assigned, we haven't lifted the edge yet
            if not src!.intree[e.index] and not IsBound(face[e.right.index][1].elt) then
                face[e.right.index] := LIFTEDGE@(target,ratmap,face[f.index],face[e.right.index],e);
                Add(todo,e.right);
            fi;
        od;
    od;

    # then lift edges cutting the tree; store group elements and permutations
    # in [perm,state]
    perm := [];
    state := [];
    for e in src!.treeedge do
        lifts := LIFTEDGE@(target,ratmap,face[e.left.index],face[e.right.index],e);
        p := [];
        s := [];
        for i in [1..Length(lifts)] do
            j := PositionProperty(face[e.right.index],f->IsIdenticalObj(lifts[i].pos,f.pos));
            Add(p,j);
            Add(s,lifts[i].elt/face[e.right.index][j].elt);
        od;
        Add(perm,p);
        Add(state,s);
    od;

    # lift points, if present -- this should give an approximation of the measure of maximal entropy
    if IsBound(src!.points) then
        target!.points := [];
        for i in src!.points do
            Add(target!.points, Random(P1PreImages(ratmap,i)));
        od;
    fi;

    return [state,perm];
end);

BindGlobal("POSTCRITICALPOINTSX@", function(f, expectedNumCriticalPoints )
    # return [poly,[critical points],[post-critical points],[transitions]]
    # where poly=true/false says if there is a fixed point of maximal degree;
    # it is then the last element of <post-critical points>
    # critical points is a list of [point in P1,degree]
    # post-critical points are points in P1
    # post-critical graph is a list of [i,j,n] meaning pcp[i] maps to pcp[j]
    # with local degree n>=1; or, if i<0, then cp[-i] maps to pcp[j].

    local c, i, j, cp, pcp, n, deg, newdeg, poly, polypos,
          transitions, src, dst;

    deg := DegreeOfP1Map(f);
    cp := List(CriticalPointsOfP1Map(f),x->[x,2]);
    i := 1;
    while i<=Length(cp) do
        j := i+1;
        while j<= Length(cp) do
            if P1Distance(cp[i][1],cp[j][1])<@.p1eps then
                Add(cp[i],Remove(cp,j)[1]);
                cp[i][2] := cp[i][2]+1;
            else
                j := j+1;
            fi;
        od;
        i := i+1;
    od;
    Info(InfoFR,3,"Barycentre");
    for c in cp do
        if Length(c)>2 then
            c[1] := P1Barycentre(c{Concatenation([1],[3..Length(c)])});
            while Length(c)>2 do Remove(c); od;
        fi;
    od;
    
    poly := First([1..Length(cp)],i->cp[i][2]=deg and P1Distance(P1Image(f,cp[i][1]),cp[i][1])<@.p1eps);
    
    pcp := [];
    transitions := [];
    n := 0;
    for i in [1..Length(cp)] do
        c := cp[i][1];
        src := -i;
        deg := cp[i][2];
        repeat
            Info(InfoFR,4,"repeat");
            c := P1Image(f,c);
            j := PositionProperty(cp,x->P1Distance(c,x[1])<@.p1eps);
            if j<>fail then
                c := cp[j][1];
                newdeg := cp[j][2];
            else
                newdeg := 1;
            fi;
            dst := PositionProperty(pcp,d->P1Distance(c,d)<@.p1eps);
            if dst=fail then
                if j=fail then
                    Add(pcp,c);
                else
                    Add(pcp,cp[j][1]);
                fi;
                if RemInt(Length(pcp),100)=0 then
                    Info(InfoFR,2,"Post-critical set contains at least ",Length(pcp)," points");
                fi;
                if expectedNumCriticalPoints<Length(pcp) then
                   Print("too mamy Post-critical points");
                   Info(InfoFR,2,"too mamy Post-critical points");
                   return fail;
                fi;
                dst := Length(pcp);
                Info(InfoFR,4,"Add transitions"); 
                Add(transitions,[src,dst,deg]);
                n := n+1;
                if IsInt(poly) and IsIdenticalObj(pcp[n],cp[poly][1]) then
                    polypos := n;
                    poly := true;
                fi;
            else
                Info(InfoFR,4,"Add transitions and break"); 
                Add(transitions,[src,dst,deg]);
                break;
            fi;
            deg := newdeg;
            src := dst;
        until false;
    od;

    if poly=fail then
        poly := false;
    else
        Add(pcp,Remove(pcp,polypos)); # force infinity to be at end
        for c in transitions do
            for i in [1..2] do
                if c[i]=polypos then
                    c[i] := n;
                elif c[i]>polypos then
                    c[i] := c[i]-1;
                fi;
            od;
        od;
    fi;

    return [poly,cp,pcp,transitions];
end);


BindGlobal("POSTCRITICALPOINTS@", function(f)
    # return [poly,[critical points],[post-critical points],[transitions]]
    # where poly=true/false says if there is a fixed point of maximal degree;
    # it is then the last element of <post-critical points>
    # critical points is a list of [point in P1,degree]
    # post-critical points are points in P1
    # post-critical graph is a list of [i,j,n] meaning pcp[i] maps to pcp[j]
    # with local degree n>=1; or, if i<0, then cp[-i] maps to pcp[j].

 return POSTCRITICALPOINTSX@(f,infinity);
end);


BindGlobal("ATTRACTINGCYCLES@", function(pcdata)
    local cycle, period, len, next, i, j, jj, periodic, critical;
    
    cycle := [];
    next := [];
    period := [];
    for i in [1..Length(pcdata[3])] do
        critical := false; periodic := false;
        j := i; jj := i;
        repeat
            jj := First(pcdata[4],x->x[1]=jj)[2];
            jj := First(pcdata[4],x->x[1]=jj)[2];
            j := First(pcdata[4],x->x[1]=j)[2];
        until j=jj;
        len := 0;
        repeat
            len := len+1;
            periodic := periodic or i=j;
            j := First(pcdata[4],x->x[1]=j);
            critical := critical or j[3]>1;
            j := j[2];
        until j=jj;
        if critical and periodic then
            Add(cycle,pcdata[3][i]);
            Add(next,i);
            Add(period,len);
        fi;
    od;
    next := List(next,i->Position(next,First(pcdata[4],x->x[1]=i)[2])-1);
    return TransposedMat([cycle,next,period]);
end);

BindGlobal("RAT2FRMACHINE@", function(f)
    local i, poly, pcdata, pcp, spider, m;

    MAKEP1EPS@();
    
    pcdata := POSTCRITICALPOINTS@(f);
    poly := pcdata[1];
    pcp := pcdata[3];
    Info(InfoFR,2,"Post-critical points at ",pcdata[3]);

    spider := TRIVIALSPIDER@(pcp);
    m := LIFTSPIDER@(spider,spider,f,poly);
    Add(m,spider);
    Add(m,poly);
    
    spider!.map := f;
    spider!.cycle := ATTRACTINGCYCLES@(pcdata);

    return m;
end);

InstallMethod(FRMachine, "(FR) for a rational function",
        [IsP1Map],
        function(f)
    local m, x, g;
    
    f := AsP1Map(f);
    x := RAT2FRMACHINE@(f);
    m := FRMachine(x[3]!.model, x[1], x[2]);
    SetSpider(m, x[3]);
    SetRationalFunction(m,f);

    return m;
end);

BindGlobal("NORMALIZEADDINGMACHINE@", function(model,trans,out,adder)
    # conjugate the recursion so that element adder, which is checked to
    # be an adding machine, becomes of the form (t,...,1)s,
    # where s is the cycle i|->i-1 mod d.
    # adder is the position of the adding element.
    # model is the ambient fundamental group.
    local cycle, deg, perm, x, i, j, basis;
    
    deg := Length(trans[1]);
    cycle := Cycles(PermList(out[adder]),[1..deg]);
    while Length(cycle)<>1 or not IsConjugate(model,Product(trans[adder]{cycle[1]}),model.(adder)) do
        Error("Element #",adder," is not an adding element");
    od;
    
    perm := PermList(Concatenation([deg],[1..deg-1]));
    perm := RepresentativeAction(SymmetricGroup(deg),PermList(out[adder]),perm);
    REORDERREC@([trans,out],perm);

    basis := [];
    x := One(model);
    for i in [deg,deg-1..1] do
        basis[i] := x;
        x := x*trans[adder][i];
    od;
    basis := RepresentativeAction(model,model.(adder),x)*basis;
    for i in [1..Length(trans)] do
        for j in [1..deg] do
            trans[i][j] := basis[j]*trans[i][j]/basis[out[i][j]];
        od;
    od;
end);

BindGlobal("IMGRECURSION@", function(to,from,trans,out,poly)
    # <trans,out> describe a recursion from spider <from> to spider <to>;
    # each line corresponds to a generator of <from>.group.
    # if poly, then last generator is assumed to correspond to fixed element
    # of maximal degree; put it in standard form.
    # returns: [ <newtrans> <newout> ], where now
    # each line corresponds to a generator of <from>.model, and each
    # entry in <newtrans>[i] is an element of <to>.model.
    local recur, r, j, v;
    
    recur := COMPOSERECURSION@(trans,out,from!.marking,to!.marking);
    IMGOPTIMIZE@(recur[1], recur[2], SPIDERRELATOR@(to),false);
    
    if poly then
        NORMALIZEADDINGMACHINE@(to!.model,recur[1],recur[2],Length(recur[1]));
        IMGOPTIMIZE@(recur[1], recur[2], SPIDERRELATOR@(to), false);
        
        # try to conjugate to simpler form, preserving the adder
        v := Source(to!.marking).(Length(recur[1]));
        v := REDUCEINNER@(Flat(recur[1]),[v,v^-1],NFFUNCTION@(to));
    else
        v := REDUCEINNER@(Flat(recur[1]),GeneratorsOfMonoid(Source(to!.marking)),NFFUNCTION@(to));
    fi;
    if not IsOne(v) then
        for r in recur[1] do for j in [1..Length(r)] do r[j] := r[j]^v; od; od;
        IMGOPTIMIZE@(recur[1], recur[2], SPIDERRELATOR@(to), false);
    fi;
    return recur;
end);

InstallMethod(IMGMachine, "(FR) for a P1 map",
        [IsP1Map],
        function(f)
    local x, m, spider, poly;
    
    f := AsP1Map(f);
    x := RAT2FRMACHINE@(f);
    spider := x[3];
    poly := x[4];
    IMGMARKING@(spider,FreeGroup(Length(x[1])+1));
    x := IMGRECURSION@(spider,spider,x[1],x[2],poly);

    m := FRMachine(spider!.model, x[1], x[2]);
    SetIMGRelator(m, SPIDERRELATOR@(spider));
    SetSpider(m, spider);
    SetRationalFunction(m, f);
    if poly then
        SetAddingElement(m,FRElement(m,spider!.model.(Length(x[1]))));
    fi;

    return m;
end);
##############################################################################

#############################################################################
##
#M IMG Machine to Function
##
InstallMethod(IMGORDERING@, [IsIMGMachine],
        function(M)
    local w;
    w := LetterRepAssocWord(IMGRelator(M));
    if ForAny(w,IsNegInt) then w := -Reversed(w); fi;
    while w[Length(w)]<>Length(w) do
        Add(w,Remove(w,1));
    od;
    return w;
end);

InstallMethod(VERTICES@, [IsMarkedSphere],
        function(spider)
    # the vertices a spider lies on
    return List(Filtered(spider!.cut!.v,v->not IsBound(v.fake)),v->v.pos);
end);

BindGlobal("STRINGTHETAPHI@", function(point)
    return CONCAT@(ATAN2_MACFLOAT(point[2],point[1])," ",
                   ACOS_MACFLOAT(point[3]));
end);

BindGlobal("SOLVE_HURWITZ@", function(d,v,c,f)
    # d is list of degrees
    # v is list of critical values, with last three (0,1,infinity) omitted
    # c is approximation to critical points
    # f is approximation to rational map
    # returns [newc,newf] using Newton's method
    local z, num, den, status, i, degree, d8;
    
    Error("This code is experimental! Proceed at your own risk.");

    z := IndeterminateOfUnivariateRationalFunction(f);
    num := ShallowCopy(CoefficientsOfUnivariatePolynomial(NumeratorOfRationalFunction(f)));
    den := ShallowCopy(CoefficientsOfUnivariatePolynomial(DenominatorOfRationalFunction(f)));
    c := ShallowCopy(c);
    degree := (Sum(d)-Length(d))/2+1;
    d8 := d[Length(d)];
    if Length(num)=degree and Length(den)=degree-d8 then
        i := Sqrt(d8*num[degree]*den[degree-d8]);
        num := num/i; den := den/i;
    fi;    
    
    status := FIND_RATIONALFUNCTION(d,v,c,num,den,[1000,@.ratprec,@.ratprec]);
    
    if status<>0 then
        return status;
    fi;
    
    return [c,P1MapByCoefficients(num,den)];
end);

BindGlobal("RUNCIRCLEPACK@", function(values,perm,oldf,oldlifts)
    local spider, s, output, f, i, j, p;

    spider := TRIVIALSPIDER@(values);
    IMGMARKING@(spider,FreeGroup(Length(values)));
    f := GroupHomomorphismByImagesNC(spider!.model,SymmetricGroup(Length(perm[1])),GeneratorsOfGroup(spider!.model),List(perm,PermList));
    s := "";
    output := OUTPUTTEXTSTRING@(s);

    PrintTo(output,"SLITCOUNT: ",Length(spider!.treeedge),"\n");
    for i in spider!.treeedge do
        PrintTo(output,STRINGTHETAPHI@(i.from.pos)," ",STRINGTHETAPHI@(i.to.pos),"\n");
    od;

    PrintTo(output,"\nPASTECOUNT: ",Length(spider!.treeedge)*Length(perm[1]),"\n");
    for i in [1..Length(spider!.treeedge)] do
        p := PreImagesRepresentative(spider!.marking,spider!.group.(i))^f;
        for j in [1..Length(perm[1])] do
            PrintTo(output,j," ",2*i-1," ",j^p," ",2*i,"\n");
        od;
    od;
    Print(s);
    CHECKEXEC@("mycirclepack");
    output := "";
    Process(DirectoryCurrent(), EXEC@.mycirclepack, InputTextString(s),
            OUTPUTTEXTSTRING@(output), []);
    Error("Interface to circlepack is not yet written. Contact the developers for more information. Output is ", output);
end);

BindGlobal("TRICRITICAL@", function(z,perm)
    # find a rational function with critical values 0,1,infinity
    # with monodromy actions perm[1],perm[2],perm[3]
    # return fail if it's too hard to do;
    # otherwise, return [map, critical points (on sphere),order],
    # where order is a permutation of the critical values:
    # ELM_LIST([0,1,infinity],order[i]) has permutation perm[i]
    
    # the cases covered are:
    # [[a],[b],[c]], degree=(a+b+c-1)/2
    # [[m,n],[m,n],[3]], degree=m+n
    # [[2,3],[2,3],[2,2]], degree=5
    # [[n,n],[2,...,2],[2,...,2]], degree=2n
    # [[degree],[m,degree-m+1]]
    # [[degree],[m,degree-m],[2]]
    local deg, cl, i, j, k, m, points, f, order, p;

    deg := Length(perm[1]);
    perm := List(perm,PermList);
    cl := List(perm,x->SortedList(CycleLengths(x,[1..deg])));
    
    points := [P1zero, P1one, P1infinity];
    
    if ForAll(cl,x->Length(DifferenceLists(x,[1]))=1) then # [[a],[b],[c]]
        cl := List(cl,x->DifferenceLists(x,[1])[1]);

        m := List([0..deg-cl[2]],row->List([0..deg],col->(-1)^(col-row)*Binomial(cl[2],col-row)));
        p := NullspaceMat(m{1+[0..deg-cl[2]]}{1+[deg-cl[3]+1..cl[1]-1]})[1];
        p := [,p*Lcm(List(p,DenominatorRat))];
        j := p[2]*m;
        j := j / Gcd(j);
        p[3] := -j{1+[0..deg-cl[3]]};
        p[1] := j{1+[cl[1]..deg]};
        for j in [1..3] do
            p[j] := P1MapByCoefficients(@.o*p[j]{[1..deg+1-cl[j]]});
        od;
        f := z^cl[1]*p[1]/p[3];
        for j in [1..3] do
            Append(points,List(RootsFloat(p[j]),P1Point));
        od;
        return [f,points,[1,2,3]];
    fi;
    
    if Size(Set(cl))<=2 and ForAll(cl,x->DifferenceLists(x,[1])=[3] or Length(x)=2) then # [m+n,m+n,3]
        i := PositionProperty(cl,x->DifferenceLists(x,[1])=[3]);
        m := cl[1+(i mod 3)];
        f := z^m[2]*((m[1]-m[2])*z+(m[1]+m[2]))^m[1]/((m[1]+m[2])*z+(m[1]-m[2]))^m[1];
        Add(points,P1Point((m[1]+m[2])/(m[2]-m[1])));
        k := P1PreImages(f,P1one);
        SortParallel(List(k,x->P1Distance(x,P1one)),k);
        Append(points,k{[4..deg]});
        if i=2 then order := [1,2,3]; else order := ListPerm((i,2),3); fi;
        return [f,points,order];
    fi;
    
    if deg=5 and IsEqualSet(cl,[[2,3],[1,2,2]]) then # (1,2)(3,4,5),(1,3)(2,5,4),(1,5)(2,3)
        f := z^3*((4*z+5)/(5*z+4))^2;
        Add(points,P1Point(-4/5)); # to infinity
        Add(points,P1Point(-5/4)); # to 0
        Add(points,P1Point((-7+Sqrt(-15*@.o))/8)); # to 1
        Add(points,P1Point((-7-Sqrt(-15*@.o))/8)); # to 1
        order := Permuted([1,3,2],(1,2,3)^Position(cl,[1,2,2]));
        return [f,points,order];
    fi;
    
    i := First([1..3],i->cl[i]=[deg/2,deg/2]);
    if i<>fail and ForAll([1..3],j->i=j or Set(cl[j])=[2]) then
        # deg = 2n; shapes [n,n],[2,...,2],[2,...,2]
        f := 4*z^(deg/2)/(1+z^(deg/2))^2;
        order := Permuted([3,2,1],(1,2,3)^i);
        Remove(points,2); # remove 1
        Append(points,List([0..deg-1],i->P1Point(Exp(@.2ipi*i/deg))));
        return [f,points,order];
    fi;
    
    i := First([1..3],i->cl[i]=[deg]); # max. cycle
    if i=fail then return fail; fi; # now only accept polynomials
    if Product(perm)=() then
        j := i mod 3+1; k := j mod 3+1;
    else
        k := i mod 3+1; j := k mod 3+1;
    fi;
    
    m := First([j,k],i->Length(cl[i])=2);
    if m<>fail then # [d],[m,d-m], [2,1,...,1]
        order := [m,j+k-m,i];
        m := cl[m][1];
        f := (z*deg/m)^m*((1-z)*deg/(deg-m))^(deg-m);
        points := points{order};
        Add(points,P1Point(m/deg));
        i := P1PreImages(f,P1one);
        SortParallel(List(i,z->P1Distance(z,P1Point(m/deg))),i);
        Append(points,i{[3..deg]});
        return [f,points,order];
    fi;
    
    m := Maximum(cl[j]);
    if Set(cl[j])=[1,m] and Set(cl[k])=[1,deg-m+1] then
        # so we know the action around i is (1,...,deg), at infinity
        # the action around j is (m,m-1,...,1), at 0
        # the action around k in (deg,deg-1...,m), at 1
        f := m*Binomial(deg,m)*Primitive(z^(m-1)*(1-z)^(deg-m));
        order := [j,k,i];
        points := points{order};
        for i in [P1zero,P1one] do
            j := P1PreImages(f,i);
            k := List(j,x->P1Distance(x,i));
            SortParallel(k,j);
            if i=P1zero then
                j := j{[m+1..deg]};
            else
                j := j{[deg+2-m..deg]};
            fi;
            Append(points,j);
        od;
        return [f,points,order];
    fi;
    
    return fail;
end);

BindGlobal("QUADRICRITICAL@", function(z,perm,values)
    local c, w, f, m, id, aut;
    
    # normalize values to be 0,1,infty,w
    aut := MoebiusMap(values{[1..3]});
    w := P1Coordinate(P1Image(InverseP1Map(aut),values[4]));
    
    # which two values have same deck transformation?
    id := First(Combinations(4,2),p->perm[p[1]]=perm[p[2]]);
    
    c := RootsFloat((z-2)^3*z-w*(z+1)^3*(z-1));
    
    # find appropriate c
    f := List(c,c->z^2*(c*(z-1)+2-c)/(c*(z+1)-c));
    m := List(f,f->IMGMachine(z,f));
    
    f := CompositionP1Map(aut,f[First([1..Length(c)],i->Output(m[i],id[1])=Output(m[i],id[2]))]);
    
    return [f, [P1zero, P1one, P1infinity, P1Point(c*(c-2)/(c^2-1))]];
end);

BindGlobal("RATIONALMAP@", function(z,values,perm,oldf,oldlifts)
    # find a rational map that has critical values at <values>, with
    # monodromy action given by <perm>, a list of permutations (as lists).
    # returns [map,points] where <points> is the full preimage of <values>
    local cv, p, f, points, deg, i;
    cv := Filtered([1..Length(values)],i->not ISONE@(perm[i]));
    deg := Length(perm[1]);
    if Length(cv)=2 then # bicritical
        f := CompositionP1Map(MoebiusMap(values{cv}),z^deg);
        points := [P1zero,P1infinity];
    elif Length(cv)=3 then # tricritical
        p := TRICRITICAL@(z,perm{cv});
        if p<>fail then
            f := CompositionP1Map(MoebiusMap(ELMS_LIST(values{cv},p[3])),p[1]);
            points := p[2];
        fi;
    elif deg=3 then # quadricritical, but degree 3
        p := QUADRICRITICAL@(z,perm{cv},values{cv});
        f := p[1];
        points := p[2];
    fi;

    if not IsBound(points) then # run circlepack
        p := RUNCIRCLEPACK@(values{cv},perm{cv},oldf,oldlifts);
        Error(p);
        f := fail;
        points := fail;
    fi;

    for i in [1..Length(values)] do if not i in cv then
        Append(points,P1PreImages(f,values[i]));
    fi; od;
    return [f,points];
end);

BindGlobal("MATCHPERMS@", function(M,q)
    # find a bijection of [1..n] that conjugates M!.output[i] to q[i] for all i
    local c, g, p;
    g := SymmetricGroup(Length(q[1]));
    p := List(GeneratorsOfGroup(StateSet(M)),g->PermList(Output(M,g)));
    q := List(q,PermList);
    c := RepresentativeAction(g,q,p,OnTuples);
    return c;
end);

BindGlobal("MATCHTRANS@", function(M,recur,spider,v)
    # match generators g[i] of M to elements of v.
    # returns a list <w> of elements of <v> such that:
    # if, in M, g[i]^N lifts to a conjugate of g[j] for some integer N, and
    # through <recur> g[i]^N lifts to a conjugate of generator h[k], then
    # set w[j] = v[k].
    # it is in particular assumed that recur[1] has as many lines as
    # StateSet(M) has generators; and that entries in recur[1][j] belong to a
    # free group of rank the length of v.
    local w, i, j, k, c, x, gensM, gensR;

    gensM := GeneratorsOfGroup(StateSet(M));
    gensR := List(GeneratorsOfGroup(spider!.model),x->x^spider!.marking);
    w := [];

    for i in [1..Length(gensM)] do
        x := WreathRecursion(M)(gensM[i]);
        Assert(0,x[2]=recur[2][i]);
        for c in Cycles(PermList(x[2]),AlphabetOfFRObject(M)) do
            j := CyclicallyReducedWord(Product(x[1]{c}));
            k := CyclicallyReducedWord(Product(recur[1][i]{c})^spider!.marking);
            if IsOne(j) then continue; fi;
            j := Position(gensM,j);
            k := PositionProperty(gensR,g->IsConjugate(spider!.group,k,g));
            w[j] := v[k];
        od;
    od;
    Assert(0,BoundPositions(w)=[1..Length(gensM)]);
    return w;
end);

BindGlobal("FINDTHREEPOINTS@", function(points)
    # returns indices [i,j,n] such that
    # n = Length(points)
    # points{[i,n]} are furthest apart
    # points[j] has maximal distance to points{[i,n]}
    local s, n, i, l, d, maxd;
    
    n := Length(points);
    s := [n];
    d := List([1..n],i->10*@.ro);
    for l in [2..3] do
        maxd := @.rz;
        for i in [1..n] do
            d[i] := Minimum(d[i],P1Distance(points[i],points[s[l-1]]));
            if d[i]>maxd then
                s[l] := i;
                maxd := d[i];
            fi;
        od;
    od;
    return s;
end);    
    
BindGlobal("NORMALIZINGMAP@", function(points,oldpoints)
    # returns the (matrix of) Möbius transformation that sends v[n] to infinity,
    # the barycenter to 0, and makes the new points as close as possible
    # to oldpoints by a rotation fixing 0-infinity.
    # oldpoints is allowed to be 'fail', in which case we just return a good
    # möbius transformation.
    local map, prec, barycenter, dilate, start, rpoints;
    
    # assuming oldpoints[n]=infinity and there are l,m such that
    # oldpoints[l] is not far from 0 and oldpoints[m] is not far from 1,
    # returns the Möbius transformation that sends points[n] to infinity,
    # points[l] to 0 and points[m] to 1.
    if oldpoints<>fail then
        start := FINDTHREEPOINTS@(oldpoints);
        map := MoebiusMap(points{start},oldpoints{start});
        if Sum([1..Length(points)],i->P1Distance(P1Image(map,points[i]),oldpoints[i]))<Length(points)*@.fast then
            return map;
        fi;
    fi;
    
    prec := 1.e-10_l; # no sense in seeking more precision; maybe less?
    start := [0._l,0._l,0._l];
    rpoints := List(points,p->List(SphereP1(p),x->NewFloat(IsIEEE754FloatRep,x)));
    while true do
        barycenter := FIND_BARYCENTER(rpoints,start,100,prec);
        if IsString(barycenter) then
            prec := 2._l*prec;
            while prec>0.001_l do # this is hopeless. we got stuck.
                Error("FIND_BARYCENTER returned '",barycenter,"'. Repent.");
            od;
        else
            break;
        fi;
    od;
    barycenter := List(barycenter[1],x->NewFloat(@.isr,x));
    
    dilate := Sqrt(barycenter^2);
    if dilate = @.rz then
        map := P1z;
    else
        map := P1ROTATION@([P1Sphere(-barycenter/dilate)],@.ro-dilate);
        points := List(points,p->P1Image(map,p));
    fi;
    return CompositionP1Map(P1ROTATION@(points,oldpoints),map);
end);

BindGlobal("SPIDERDIST@", function(spiderA,spiderB,fast)
    local model, points, perm, dist, recur, endo, nf, g;

    model := spiderA!.model;

    # try to match feet of spiderA and spiderB
    points := VERTICES@(spiderA);
    perm := VERTICES@(spiderB);
    
    perm := MATCHPOINTS@(perm,List(perm,x->points));
    if perm=fail or Set(perm)<>[1..Length(points)] then # no match, find something coarse
        return @.ro*Sum(GeneratorsOfGroup(spiderA!.group),x->Length(PreImagesRepresentative(spiderA!.marking,x)^spiderB!.marking))/Length(points);
    fi;
    
    
    # move points of spiderB to their spiderA matches
    spiderB := COPYSPIDER@(spiderB,points{perm});
    dist := spiderB!.cut!.wiggled;
    
    if fast then # we just wiggled the points, the combinatorics didn't change
        return dist/Length(points);
    fi;
    
    recur := LIFTSPIDER@(spiderA,spiderB,P1z,false);

    if Group(Concatenation(recur[1]))<>spiderA!.group then
        Info(InfoFR,1,"The triangulation got messed up; cross your fingers");
    fi;

    endo := GroupHomomorphismByImagesNC(spiderB!.group,model,
                    GeneratorsOfGroup(spiderB!.group),
        List(recur[1],x->PreImagesRepresentative(spiderA!.marking,x[1])))*spiderB!.marking;

    endo := List(GeneratorsOfGroup(spiderB!.group),x->x^endo);
    REDUCEINNER@(endo,GeneratorsOfMonoid(spiderB!.group),x->x);
    
    for g in endo do
        dist := dist + (Length(g)-1); # if each image is a gen, then endo=1
    od;
    return dist/Length(points);
end);

BindGlobal("PUSHRECURSION@", function(map,M)
    # returns a WreathRecursion() function for Range(map), and not
    # Source(map) = StateSet(M)
    local w;
    w := WreathRecursion(M);
    return function(x)
        local l;
        l := w(PreImagesRepresentative(map,x));
        return [List(l[1],x->Image(map,x)),l[2]];
    end;
end);

BindGlobal("PULLRECURSION@", function(map,M)
    # returns a WreathRecursion() function for Source(map), and not
    # Range(map) = StateSet(M)
    local w;
    w := WreathRecursion(M);
    return function(x)
        local l;
        l := w(Image(map,x));
        return [List(l[1],x->PreImagesRepresentative(map,x)),l[2]];
    end;
end);

BindGlobal("PERRONMATRIX@", function(mat)
    local i, j, len;
    # find if there's an eigenvalue >= 1, without using numerical methods

    len := Length(mat);
    if NullspaceMat(mat-IdentityMat(len))=[] then # no 1 eigenval
        i := List([1..len],i->1);
        j := List([1..len],i->1); # first approximation to perron-frobenius vector
        repeat
            i := i*mat;
            j := j*mat*mat; # j should have all entries growing exponentially
            if ForAll([1..len],a->j[a]=0 or j[a]<i[a]) then
                return false; # perron-frobenius eigenval < 1
            fi;
        until ForAll(j-i,IsPosRat);
    fi;
    return true;
end);

BindGlobal("SURROUNDINGCURVE@", function(t,x)
    # returns a CCW sequence of edges disconnecting x from its complement in t.
    # x is a sequence of indices of vertices. t is a triangulation.
    local starte, a, c, v, e, i;

    starte := First(t!.e,j->j.from.index in x and not j.to.index in x);
    v := starte.from;
    a := [starte.left.pos];
    c := [];
    i := POSITIONID@(v.n,starte);
    repeat
        i := i+1;
        if i > Length(v.n) then i := 1; fi;
        e := v.n[i];
        if e.to.index in x then
            v := e.to;
            e := e.reverse;
            i := POSITIONID@(v.n,e);
        else
            Add(c,e);
            Add(a,e.pos);
            Add(a,e.left.pos);
        fi;
    until IsIdenticalObj(e,starte);
    return [a,c];
end);

BindGlobal("FINDOBSTRUCTION@", function(M,multicurve,spider,boundary)
    # search for an obstruction starting with the elements of M.
    # return fail or a record describing the obstruction.
    # spider and boundary may be "fail".
    local len, w, x, mat, row, i, j, c, d, group, pi, gens, peripheral;

    len := Length(multicurve);
    gens := GeneratorsOfGroup(StateSet(M));
    group := FreeGroup(Length(gens)-1);
    c := IMGRelator(M);
    pi := GroupHomomorphismByImagesNC(StateSet(M),group,List([1..Length(gens)],i->Subword(c,i,i)),Concatenation(GeneratorsOfGroup(group),[Product(List(Reversed(GeneratorsOfGroup(group)),Inverse))]));

    w := PUSHRECURSION@(pi,M);

    peripheral := List(GeneratorsOfSemigroup(StateSet(M)),x->CyclicallyReducedWord(x^pi));
    multicurve := List(multicurve,x->CyclicallyReducedWord(x^pi));
    mat := [];
    for i in multicurve do
        d := w(i);
        row := List([1..len],i->0);
        for i in Cycles(PermList(d[2]),AlphabetOfFRObject(M)) do
            c := CyclicallyReducedWord(Product(d[1]{i}));
            if ForAny(peripheral,x->IsConjugate(group,x,c)) then
                continue; # peripheral curve
            fi;
            j := First([1..len],j->IsConjugate(group,c,multicurve[j])
                       or IsConjugate(group,c^-1,multicurve[j]));
            if j=fail then # add one more curve
                for j in mat do Add(j,0); od;
                Add(row,1/Length(i));
                len := len+1;
                Add(multicurve,c);
            else
                row[j] := row[j] + 1/Length(i);
            fi;
        od;
        Add(mat,row);
    od;

    Info(InfoFR,2,"Thurston matrix is ",mat);

    x := List(EquivalenceClasses(StronglyConnectedComponents(BinaryRelationOnPoints(List([1..len],x->Filtered([1..len],y->IsPosRat(mat[x][y])))))),Elements);
    for i in x do
        if PERRONMATRIX@(mat{i}{i}) then # there's an eigenvalue >= 1
            d := rec(machine := M,
                     obstruction := [],
                     matrix := mat{i}{i});
            if spider<>fail then
                d.spider := spider;
            fi;
            for j in i do
                if spider<>fail and IsBound(boundary[j]) then
                    if not IsBound(spider!.arcs) then spider!.arcs := []; fi;
                    Add(spider!.arcs,[[0,0,255],Float(105/100),boundary[j][1]]);
                fi;
                c := [PreImagesRepresentative(pi,multicurve[j])];
                if spider<>fail then
                    REDUCEINNER@(c,GeneratorsOfMonoid(StateSet(M)),NFFUNCTION@(spider));
                fi;
                Append(d.obstruction,c);
            od;
            return d;
        fi;
    od;
    return fail;
end);

InstallOtherMethod(FindThurstonObstruction, "(FR) for a list of IMG elements",
#        [IsIMGElementCollection], !method selection doesn't work!
        [IsFRElementCollection],
        function(elts)
    local M;
    M := UnderlyingFRMachine(elts[1]);
    while not IsIMGMachine(M) or ForAny(elts,x->not IsIdenticalObj(M,UnderlyingFRMachine(x))) do
        Error("Elements do not all have the same underlying IMG machine");
    od;
    return FINDOBSTRUCTION@(M,List(elts,InitialState),fail,fail);
end);

BindGlobal("SPIDEROBSTRUCTION@", function(spider,M)
    # check if <spider> has coalesced points; in that case, read the
    # loops around them and check if they form an obstruction
    local multicurve, boundary, i, j, c, d, x, w;

    # construct a list <x> of (lists of vertices that coalesce)
    w := VERTICES@(spider);
    x := Filtered(Combinations([1..Length(w)],2),p->P1Distance(w[p[1]],w[p[2]])<@.obst);
    x := EquivalenceClasses(EquivalenceRelationByPairs(Domain([1..Length(w)]),x));
    x := Filtered(List(x,Elements),c->Size(c)>1);
    if x=[] then
        return fail;
    fi;

    # replace each x by its conjugacy class
    multicurve := [];
    boundary := [];
    for i in x do
        c := One(spider!.group);
        for j in TREEBOUNDARY@(spider) do
            if (not j.from.index in i) and j.to.index in i then
                c := c*j.gpelement;
            fi;
        od;
        Add(multicurve,c);
        Add(boundary,SURROUNDINGCURVE@(spider!.cut,i));

    od;
    Info(InfoFR,2,"Testing multicurve ",multicurve," for an obstruction");

    return FINDOBSTRUCTION@(M,List(multicurve,x->PreImagesRepresentative(spider!.marking,x)),spider,boundary);
end);

BindGlobal("NORMALIZEV@", function(f,M,param)
    # param is IsPolynomial, IsBicritical, or a positive integer.
    # in the first case, normalize f as z^d+a_{d-2}*z^{d-2}+...+a_0
    # in the second case, normalize f as (az^d+b)/(cz^d+e)
    # in the third case, normalize f as 1+a/z+b/z^2, such that 0 is on
    # a cycle of length <param>
    # return [new map, Möbius transformation from old to new]
    local p, i, j, k, a, b, mobius, m, coeff, degree, numer, denom, z;
    z := IndeterminateOfUnivariateRationalFunction(f);
    p := POSTCRITICALPOINTS@(f);
    degree := DegreeOfP1Map(f);
    
    if param=fail then
        if IsPolynomialIMGMachine(M) then
            param := IsPolynomial;
        else
            return fail;
        fi;
    fi;
    while not IsPosInt(param) and param<>IsPolynomial and param<>IsBicritical do
        Error("NORMALIZEV@: parameter should be 'IsPolynomial', 'IsBicritical' or a positive integer");
    od;
        
    mobius := MoebiusMap(p[2][1][1], p[2][2][1]); # send 2 first c.p. to 0,infty
    
    if param=IsBicritical then # force critical points at 0, infty; make first other point 1
        while Length(p[2])>2 do
            Error("The map is not bicritical, I don't know how to normalize it");
        od;
        j := First(p[3],z->not IsIdenticalObj(z,p[2][1][1]) and not IsIdenticalObj(z,p[2][2][1]));
        if j=fail then # no other point; then map is z^{\pm degree}
            if p[1] then
                return [z^degree,mobius];
            else
                return [z^(-degree),mobius];
            fi;
        fi;
    elif param=IsPolynomial then
        j := fail;
        for i in [1..Length(p[2])] do
            k := First(p[4],r->r[1]=-i)[2];
            if [k,k,degree] in p[4] then j := k; break; fi;
        od;
        while not p[1] or j=fail do
            Error("Map is not a polynomial");
        od;
        if Length(p[3])=2 then
            return [z^degree,mobius];
        fi;
        i := CleanedP1Map(CompositionP1Map(InverseP1Map(mobius),f,mobius),@.p1eps); # polynomial
        coeff := CoefficientsOfP1Map(i);
        mobius := CompositionP1Map(mobius,P1MapSL2([[@.o/coeff[1][degree+1]^(1/(degree-1)),-coeff[1][degree]/degree/coeff[1][degree+1]],[@.z,@.o]]));
        m := P1MapSL2([[Exp(@.2ipi/(degree-1)),@.z],[@.z,@.o]]);
        j := SupportingRays(M);
        repeat
            k := SupportingRays(IMGMachine(CompositionP1Map(InverseP1Map(mobius),f,mobius)));
            if k=j then break; fi; #!!! maybe should be: "equivalent"rays?
            mobius := mobius*m;
            Info(InfoFR,1,"param:=IsPolynomial: trying to rotate around infinity");
        until false;
    else # parameterize on slice V_n
        while degree<>2 do
            Error("'param:=<positive integer>' only makes sense for degree-2 maps");
        od;
        for i in [1..2] do
            j := [First(p[4],r->r[1]=-i)[2]];
            for k in [1..param] do
                j[k+1] := First(p[4],r->r[1]=j[k])[2];
            od;
            if j[param+1]=j[1] and not j[1] in j{[2..param]} then j := j[1]; break; fi;
        od;
        while not IsInt(j) do
            Error("I couldn't find a cycle of length ",param);
        od;
        if param=1 then # map marked point to infty, unmarked to 0, 0=>1
            if Length(p[3])=2 then
                return [z^degree,mobius];
            fi;
            j := First(p[4],r->r[1]=i-3)[2];
            mobius := MoebiusMap(p[2][3-i][1],p[3][j],p[2][i][1]);
        elif param=2 then # normalize as a/(z^2+2z), infty=>0->infty, -1=>
            if Length(p[3])=2 then # special case infty=>0=>infty or polynomial
                if First(p[4],r->r[1]=j)[2]=j then
                    return [z^degree,mobius];
                else
                    return [z^(-degree),mobius];
                fi;
            fi;
            mobius := CompositionP1Map(MoebiusMap(p[3][j],p[2][3-i][1],p[2][i][1]),-z);
        else # normalize as 1+a/z+b/z^2, 0=>infty->1
            k := First(p[4],r->r[1]=j)[2];
            mobius := MoebiusMap(p[2][i][1],p[3][k],p[3][j]);
        fi;
    fi;
    f := CleanedP1Map(CompositionP1Map(InverseP1Map(mobius),f,mobius),@.p1eps);
    numer := List([0..degree],i->@.z);
    denom := List([0..degree],i->@.z);
    if param=2 then # special cleanup
        coeff := CoefficientsOfP1Map(f);
        if IsZero(coeff[1][2]) and IsZero(coeff[1][3]) and IsZero(coeff[2][1]) and AbsoluteValue(coeff[2][3]-1/2)<@.ratprec then
            numer[1] := coeff[1][1]*2; # numerator is A
            denom[2] := @.o; # denominator is z+z^2/2, off by 2 now
            denom[3] := @.o/2;
            f := CleanedP1Map(P1MapByCoefficients(numer,denom),@.p1eps);
            coeff := CoefficientsOfP1Map(f);
            f := P1MapByCoefficients(coeff[1],2*coeff[2]);
        else
            Error("Cannot normalize to A/(z^2+2z)");
        fi;
    elif param=3 then # special cleanup, force 1+a+b=0
        coeff := CoefficientsOfP1Map(f);
        if AbsoluteValue(Sum(coeff[1]))<@.ratprec and AbsoluteValue(coeff[1][3]-1)<@.ratprec then
            numer[1] := coeff[1][1];
            numer[2] := -numer[1]-@.o;
            numer[3] := @.o;
            denom[3] := @.o;
            f := P1MapByCoefficients(numer,denom);
        else
            Error("Cannot normalize to (A+(-1-A)z+z^2)/z^2");
        fi;
    fi;
    return [f,mobius];
end);

BindGlobal("EQUIDISTRIBUTEDPOINTS@", function(N)
    # creates a list of N points equidistributed on the sphere
    local t, x, p, r;

    p := [];

    while Length(p)<Minimum(N,10) do # add a little randomness
        x := List([1..3],i->Random([-10^5..10^5]));
        if x<>[0,0,0] then # that would be VERY unlucky
            Add(p,P1Sphere(@.ro*x));
        fi;
    od;
    if Length(p)=N then return p; fi;
    
    t := DelaunayTriangulation(p);
    r := @.pi/2;
    while Length(t!.v)<N do
        p := First(t!.f,x->x.radius>=r);
        if p=fail then r := r*3/4; continue; fi;
        ADDTOTRIANGULATION@(t,p,p.centre);
        for x in t!.f do
            if not IsBound(x.radius) then
                p := CallFuncList(P1Circumcentre,List(x.n,e->e.from.pos));
                x.centre := p[1];
                x.radius := p[2];
            fi;
        od;
    od;
    return List(t!.v,x->x.pos);
end);

BindGlobal("SIMPLIFYBYBRAIDTWISTS@", function(m,marking)
    local bg, g, i, len, newmarking, newlen, twist, idle;

    bg := BraidTwists(m);
    g := GeneratorsOfGroup(Source(marking));
    len := infinity;
    twist := [];
    repeat
        idle := true;
        newmarking := List(bg,t->t*marking);
        newlen := List(newmarking,t->Sum(g,x->Length(x^t)));
        i := Position(newlen,Minimum(newlen));
        if newlen[i] < len then
            len := newlen[i];
            marking := newmarking[i];
            Add(twist,bg[i]);
            idle := false;
        fi;
    until idle;
    
    return List(Reversed(twist),Inverse);
end);

BindGlobal("FRMACHINE2RAT@", function(z,M)
    local oldspider, spider, t, gens, n, deg, model,
          f, mobius, match, v, i, j, recf, recmobius, map,
          dist, obstruction, lifts, sublifts, fast, poly;

    MAKEP1EPS@();
    
    model := StateSet(M);
    gens := GeneratorsOfGroup(model);
    n := Length(gens);
    deg := Length(AlphabetOfFRObject(M));
    poly := IsPolynomialFRMachine(M);
    
    if n=2 then # special handling, space is not hyperbolic
        i := Sum(List(Transitions(M,1),ExponentSums));
        if i[1]-i[2]=1 then
            return z^deg;
        elif i[1]-i[2]=-1 then
            return z^(-deg);
        else
            Error(M," is not an IMG machine");
        fi;
    fi;    
    
    # create spider on +/- equidistributed points on Greenwich meridian.
    # its spanning tree will be consecutive edges from infty to 1,
    # and so its IMG ordering is predictably that of M
    v := [];
    for i in [1..n] do
        # on positive real axis, tending to infinity
        f := Exp(@.2ipi*(i-1)/(2*n-2));
        Add(v,P1Point(@.o*ImaginaryPart(f)/(@.ro+RealPart(f))));
    od;
    v := Permuted(v,PermList(IMGORDERING@(M)));
    spider := TRIVIALSPIDER@(v);
    IMGMARKING@(spider,model);

    if ValueOption("julia")<>fail then
        i := ValueOption("julia");
        if not IsInt(i) then i := 1000; fi; # number of points to trace
        spider!.points := EQUIDISTRIBUTEDPOINTS@(i);
    fi;
    
    lifts := fail;
    f := fail; # in the beginning, we don't know them
    fast := false;

    repeat
        oldspider := spider;
        # find a rational map that has the right critical values
        f := RATIONALMAP@(z,VERTICES@(spider),List(gens,g->Output(M,g)),f,lifts);
        lifts := f[2]; f := f[1];
        Info(InfoFR,3,"1: found rational map ",f," on vertices ",lifts);

        if fast then # just get points closest to those in spider t
            match := MATCHPOINTS@(sublifts,List(sublifts,x->lifts));
            if match=fail then
		Info(InfoFR,3,"1.5: back to slow mode");
                fast := false; continue;
            fi;
            sublifts := lifts{match};
        else
            # create a spider on the full preimage of the points of <spider>
            t := TRIVIALSPIDER@(lifts);
            IMGMARKING@(t,FreeGroup(Length(lifts)));
            Info(InfoFR,3,"2: created liftedspider ",t);

            # lift paths in <spider> to <t>
            recf := LIFTSPIDER@(t,spider,f,poly);
            if recf=fail then return fail; fi;
            recf := IMGRECURSION@(t,spider,recf[1],recf[2],false);
            Assert(1, CHECKREC@(recf,spider!.ordering,NFFUNCTION@(t)));
            Info(InfoFR,3,"3: recursion ",recf);
            
            # find a bijection between the alphabets of <recf> and <M>
            match := MATCHPERMS@(M,recf[2]);
            if match=fail then return fail; fi;
            
            REORDERREC@(recf,match);
            Info(InfoFR,3,"4: alphabet permutation ",match);

            # extract those vertices in <v> that appear in the recursion
            sublifts := MATCHTRANS@(M,recf,t,lifts);
            Info(InfoFR,3,"5: extracted and sorted vertices ",sublifts);
        fi;
 
        # find a mobius transformation that normalizes <sublifts> wrt PSL2C
        mobius := NORMALIZINGMAP@(sublifts,VERTICES@(spider));
        Info(InfoFR,3,"6: normalize by mobius map ",mobius);

        # now create the new spider on the image of these points
        v := List(sublifts,p->P1Image(mobius,p));
        
	if fast then
            dist := Sum([1..Length(v)],i->P1Distance(VERTICES@(spider)[i],v[i]));
            if dist>@.fast*Length(v) then
                fast := false;
                Info(InfoFR,3,"7: legs moved ",dist,"; back to slow mode");
                spider := oldspider;
                continue; # restart
            fi;
            # just wiggle spider around
            spider := COPYSPIDER@(spider,v);
        else
            spider := TRIVIALSPIDER@(v);
            recmobius := LIFTSPIDER@(spider,t,InverseP1Map(mobius),poly);
            if recmobius=fail then
                return fail;
            else
                recmobius := recmobius[1];
            fi;
            Info(InfoFR,3,"7: new spider ",spider," with recursion ",recmobius);

            # compose recursion of f with that of mobius
            map := t!.marking*GroupHomomorphismByImagesNC(t!.group,spider!.group,GeneratorsOfGroup(t!.group),List(recmobius,x->x[1]));
            for i in recf[1] do
                for j in [1..Length(i)] do i[j] := i[j]^map; od;
            od;
            Info(InfoFR,3,"8: composed recursion is ",recf);
                   
            # finally set marking of new spider using M
            spider!.model := model;
            spider!.ordering := oldspider!.ordering;
            spider!.marking := MATCHMARKINGS@(M,spider!.group,recf);
            Assert(1, CHECKREC@(recf,spider!.ordering,NFFUNCTION@(t)));
            Assert(1, CHECKSPIDER@(spider));
            Info(InfoFR,3,"9: marked new spider ",spider);
        fi;
        
        dist := SPIDERDIST@(spider,oldspider,fast);
        Info(InfoFR,2,"Spider moved ",dist," steps; feet=",VERTICES@(spider)," marking=",spider!.marking);

        if dist<@.ratprec then
            if fast then # force one last run with the full algorithm
                fast := false;
                continue;
            fi;
            f := CleanedP1Map(CompositionP1Map(f,InverseP1Map(mobius)),@.p1eps);
            break;
        elif dist<@.fast then
            fast := true;
        else
            fast := false;
        fi;
        obstruction := SPIDEROBSTRUCTION@(spider,M);
        if obstruction<>fail then
            return obstruction;
        fi;
    until false;
    
    Info(InfoFR,2,"Spider converged");
    
    i := NORMALIZEV@(f,M,ValueOption("param"));
    if i<>fail then
        spider := COPYSPIDER@(spider,InverseP1Map(i[2]));
        f := i[1];
    fi;
    
    # construct a new machine with simpler recursion
    for i in recf[1] do
        for j in [1..Length(i)] do
            i[j] := PreImagesRepresentative(spider!.marking,i[j]);
        od;
    od;
    IMGOPTIMIZE@(recf[1], recf[2], SPIDERRELATOR@(spider),poly);
    t := FRMachine(model, recf[1], recf[2]);
    SetIMGRelator(t, SPIDERRELATOR@(spider));
    
    # in principle, now, t is the same as M (but perhaps in a slightly
    # different basis, i.e. conjugated by an inner automorphism)
    
    # find a good twist to shorten the marking; presumably, this
    # will give a simpler machine
    i := SIMPLIFYBYBRAIDTWISTS@(M, spider!.marking);
    t := t^Product(i);
    SetCorrespondence(t,i);
    
    spider!.map := f;
    spider!.cycle := ATTRACTINGCYCLES@(POSTCRITICALPOINTS@(f));
                     
    return [f,t,spider];
end);

InstallMethod(RationalFunction, "(FR) for an IMG machine",
        [IsIMGMachine],
        M->RationalFunction(P1z,M));

InstallMethod(RationalFunction, "(FR) for an indeterminate and an IMG machine",
        [IsRingElement,IsIMGMachine],
        function(z,M)
    local data, f;
    data := FRMACHINE2RAT@(z,M);
    if not IsList(data) then return data; fi;
    f := data[1];
    SetIMGMachine(f,data[2]);
    SetSpider(f,data[3]);
    return f;
end);
#############################################################################

#E triangulations.g . . . . . . . . . . . . . . . . . . . . . . . . ends here
