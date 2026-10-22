import sys, math, cairosvg
out=sys.argv[1]
def spark(cx,cy,r,f):
    k=r*0.22
    return f'<path fill="{f}" d="M{cx},{cy-r} C{cx+k},{cy-k} {cx+k},{cy-k} {cx+r},{cy} C{cx+k},{cy+k} {cx+k},{cy+k} {cx},{cy+r} C{cx-k},{cy+k} {cx-k},{cy+k} {cx-r},{cy} C{cx-k},{cy-k} {cx-k},{cy-k} {cx},{cy-r} Z"/>'
def bg(c1,c2):
    return f'<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{c1}"/><stop offset="1" stop-color="{c2}"/></linearGradient></defs><rect width="1024" height="1024" fill="url(#bg)"/>'
def catmull(P,n=30):
    pts=[]
    P=[P[0]]+P+[P[-1]]
    for i in range(1,len(P)-2):
        p0,p1,p2,p3=P[i-1],P[i],P[i+1],P[i+2]
        for j in range(n):
            t=j/n
            pts.append(tuple(0.5*((2*p1[k])+(-p0[k]+p2[k])*t+(2*p0[k]-5*p1[k]+4*p2[k]-p3[k])*t*t+(-p0[k]+3*p1[k]-3*p2[k]+p3[k])*t**3) for k in (0,1)))
    pts.append(P[-2]); return pts
def curve(x0,x1,cy,amp,per,drop,n=200):
    c=[]
    for i in range(n+1):
        t=i/n; y=cy-amp*math.sin(2*math.pi*per*t)
        if t>0.72: y+=drop*((t-0.72)/0.28)**2
        c.append((x0+(x1-x0)*t,y))
    return c
def tapered(c,w0,w1,taper_from,col):
    L=[0]
    for a,b in zip(c,c[1:]): L.append(L[-1]+math.dist(a,b))
    tot=L[-1]; left=[];right=[]
    for i,p in enumerate(c):
        a=c[max(i-1,0)]; b=c[min(i+1,len(c)-1)]
        dx,dy=b[0]-a[0],b[1]-a[1]; n=math.hypot(dx,dy) or 1
        nx,ny=-dy/n,dx/n; t=L[i]/tot
        w=w0 if t<taper_from else w0+(w1-w0)*((t-taper_from)/(1-taper_from))**1.2
        left.append((p[0]+nx*w/2,p[1]+ny*w/2)); right.append((p[0]-nx*w/2,p[1]-ny*w/2))
    poly=left+right[::-1]
    d='M'+' L'.join(f'{x:.1f},{y:.1f}' for x,y in poly)+'Z'
    s=c[0]
    return f'<path d="{d}" fill="{col}"/><circle cx="{s[0]:.1f}" cy="{s[1]:.1f}" r="{w0/2}" fill="{col}"/>'
def svg(b): return f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">{b}</svg>'
Y="#FDE68A"; G="rgba(255,255,255,0.42)"; CY=760
bar=f'<rect x="212" y="{CY-30}" width="320" height="60" rx="30" fill="{G}"/>'
pen_old=[(588,CY+14),(622,CY-34),(662,CY+4),(700,CY+36),(742,CY-14),(780,CY-30),(812,CY+8),(826,CY+70)]
pen2_old=[(588,CY+14),(624,CY-36),(666,CY+10),(706,CY+38),(748,CY-20),(792,CY-26),(818,CY+40),(820,CY+92)]
pen=curve(590,810,CY,30,1.25,70)
pen2=curve(590,815,CY,34,1.5,90)
stars_a=[(700,250,62),(305,265,34),(268,470,22),(752,520,26),(390,155,18),(640,150,14)]
stars_b=[(700,250,62),(318,250,40),(282,452,20),(740,500,30),(408,148,16),(622,140,12),(805,375,14)]
def icon(stars,pen,bg1="#4F46E5",bg2="#7C3AED",sc=Y,pc=Y):
    b=bg(bg1,bg2)+spark(512,410,200,sc)
    for x,y,r in stars: b+=spark(x,y,r,sc)
    return svg(b+bar+tapered(pen,40,3,0.45,pc))
V={'C1':icon(stars_a,pen),'C2':icon(stars_b,pen2),'C3':icon(stars_a,pen,pc="#FFFFFF")}
for k,v in V.items():
    open(f'{out}/{k}.svg','w').write(v); cairosvg.svg2png(bytestring=v.encode(),write_to=f'{out}/{k}.png')
