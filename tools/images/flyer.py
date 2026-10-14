import sys; sys.path.insert(0,'imgwork')
from PIL import Image, ImageDraw, ImageFont
import numpy as np, cv2
SANS='payload/sourcehan_4055.otf'   # Source Han Sans TC Regular (OFL)
src=Image.open('img/chines_flyer_scn.png').convert('RGBA')
rgba=np.array(src); rgb=rgba[:,:,:3].copy(); L=rgb.astype(int).mean(2)

def glyph_alpha(ch,size,ss=4):
    f=ImageFont.truetype(SANS,size*ss)
    im=Image.new('L',(size*ss*3,size*ss*3),0); d=ImageDraw.Draw(im)
    d.text((size*ss,size*ss),ch,font=f,fill=255)   # origin at (size*ss,size*ss) top-left of em (PIL 'la' anchor)
    return im  # supersampled, em origin at (size*ss, size*ss)

def ink_bbox(mask):
    ys,xs=np.nonzero(mask); return xs.min(),ys.min(),xs.max()+1,ys.max()+1

def calibrate(ref_ch, box, is_text, sizes):
    """find font size & em-origin so rendered ref_ch matches original ink bbox"""
    x0,y0,x1,y1=box
    ox0,oy0,ox1,oy1=ink_bbox(is_text[y0:y1,x0:x1]); ox0+=x0;ox1+=x0;oy0+=y0;oy1+=y0
    best=None
    for s in sizes:
        for ss in (4,):
            g=np.array(glyph_alpha(ref_ch,s,ss))>96
            gx0,gy0,gx1,gy1=ink_bbox(g)
            w=(gx1-gx0)/ss; h=(gy1-gy0)/ss
            err=abs(w-(ox1-ox0))+abs(h-(oy1-oy0))
            if best is None or err<best[0]:
                # em origin in image coords
                ex=ox0-(gx0/ss-s); ey=oy0-(gy0/ss-s)
                best=(err,s,ex,ey)
    return best

def erase(cell,is_text,dil=2):
    x0,y0,x1,y1=cell
    m=np.zeros(L.shape,np.uint8); m[y0:y1,x0:x1]=is_text[y0:y1,x0:x1]
    m=cv2.dilate(m,np.ones((2*dil+1,2*dil+1),np.uint8))
    global rgb
    rgb=cv2.inpaint(np.ascontiguousarray(rgb),m*255,5,cv2.INPAINT_TELEA)

def draw(ch,size,ex,ey,color,boldpx=0):
    ss=4; g=glyph_alpha(ch,size,ss)
    if boldpx: g=Image.fromarray(cv2.dilate(np.array(g),np.ones((boldpx,boldpx),np.uint8)))
    W=g.width//ss; g=g.resize((W,W),Image.LANCZOS)
    a=np.array(g).astype(float)/255
    # g's em origin is at (size,size) after downscale
    X=round(ex)-size; Y=round(ey)-size
    h,w=a.shape
    reg=rgb[Y:Y+h,X:X+w].astype(float)
    rgb[Y:Y+h,X:X+w]=(reg*(1-a[...,None])+np.array(color)*a[...,None]).astype(np.uint8)

def line(spec):
    is_text=spec['mask']
    err,s,ex,ey=calibrate(spec['ref'][0],spec['ref'][1],is_text,spec['sizes'])
    ref_idx=spec['ref'][2]; pitch=spec['pitch']
    print(spec['name'],'size',s,'err',round(err,2),'pitch',pitch)
    txt=np.array(spec['color'])
    for idx,ch,cell in spec['repl']:
        erase(cell,is_text)
    for idx,ch,cell in spec['repl']:
        draw(ch,s,ex+(idx-ref_idx)*pitch,ey,spec['color'],spec.get('bold',0))

white=L>185; dark=L<130
def col(mask,box):
    x0,y0,x1,y1=box; sel=rgb[y0:y1,x0:x1][mask[y0:y1,x0:x1]]; 
    return tuple(int(v) for v in np.median(sel,0))
# line 1: 四海衣坊倾情献上   (white on teal)
l1y=(184,214)
line(dict(name='l1',mask=white,ref=('情',(315,l1y[0],344,l1y[1]),5),pitch=29.0,sizes=range(24,34),
    color=col(white&(L>215),(170,184,400,214)),
    repl=[(4,'傾',(286,l1y[0],315,l1y[1])),(6,'獻',(344,l1y[0],374,l1y[1]))]))
# line 3
l3y=(362,400)
line(dict(name='l3',mask=dark,ref=('有',(58,l3y[0],86,l3y[1]),1),pitch=28.0,sizes=range(22,34),
    color=col(L<70,(30,362,540,400)),
    repl=[(4,'獨',(142,l3y[0],170,l3y[1])),(7,'聲',(226,l3y[0],254,l3y[1])),(8,'譽',(254,l3y[0],282,l3y[1])),(12,'貴',(366,l3y[0],394,l3y[1]))]))
# line 4: …精彩远不止于此！
l4y=(878,926)
line(dict(name='l4',mask=dark,ref=('不',(335,l4y[0],380,l4y[1]),4),pitch=45.2,sizes=range(38,52),
    color=col(L<70,(200,878,515,926)),
    repl=[(3,'遠',(289,l4y[0],335,l4y[1])),(6,'於',(425,l4y[0],470,l4y[1]))]))
# line 5 (pitch 17.9; positions from measured ink starts)
l5y=(945,968)
line(dict(name='l5',mask=dark,ref=('在',(93,l5y[0],111,l5y[1]),0),pitch=1.0,sizes=range(14,22),
    color=col(L<90,(55,945,512,968)),
    repl=[(219-94,'購',(217,l5y[0],236,l5y[1])),(300-94,'問',(298,l5y[0],316,l5y[1])),(317-94,'題',(316,l5y[0],334,l5y[1])),(424-94,'們',(422,l5y[0],441,l5y[1]))]))
l6y=(968,992)
line(dict(name='l6',mask=dark,ref=('品',(218,l6y[0],236,l6y[1]),0),pitch=1.0,sizes=range(14,22),
    color=col(L<90,(160,968,405,992)),
    repl=[(255-219,'為',(253,l6y[0],271,l6y[1])),(290-219,'貴',(288,l6y[0],307,l6y[1])),(326-219,'貴',(324,l6y[0],342,l6y[1])),(344-219,'賓',(342,l6y[0],360,l6y[1])),(361-219,'預',(359,l6y[0],378,l6y[1]))]))
out=rgba.copy(); out[:,:,:3]=rgb
Image.fromarray(out).save('imgwork/flyer_tc.png')
bg=Image.new('RGBA',src.size,(255,255,255,255)); bg.alpha_composite(Image.fromarray(out)); bg=bg.convert('RGB')
bg.crop((0,160,580,420)).resize((1160,520),Image.LANCZOS).save('imgwork/flyer_tc_top.png')
bg.crop((0,860,580,1000)).resize((1160,280),Image.LANCZOS).save('imgwork/flyer_tc_bot.png')
