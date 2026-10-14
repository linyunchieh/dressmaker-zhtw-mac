import sys; sys.path.insert(0,'imgwork')
from glyph import *
from scipy import ndimage
import cv2
def build(F,IDX,title_stroke,sub_stroke,dil_title,dil_sub,out):
    src=Image.open('img/chines_newspaperSprites_scn.png').convert('RGBA')
    a=np.array(src); al=a[:,:,3].copy()
    lab,n=ndimage.label(al>0)
    objs=ndimage.find_objects(lab)
    def erase_box(x0,x1,y0,y1):
        for i,sl in enumerate(objs):
            if sl[1].start>=x0 and sl[1].stop<=x1 and sl[0].start>=y0 and sl[0].stop<=y1: al[lab==i+1]=0
    erase_box(585,792,25,230); erase_box(990,1196,25,230); erase_box(625,760,255,316); erase_box(885,1160,255,316)
    A=Image.fromarray(al)
    def g(ch,h,st,dil):
        x=fit(ch,F,IDX,h,st)
        if dil: x=Image.fromarray(cv2.dilate(np.array(x),np.ones((dil,dil),np.uint8)))
        return x
    for ch,(x0,x1) in [('餘',(591,787)),('報',(998,1191))]:
        paste_center(A,g(ch,190,title_stroke,dil_title),(x0+x1)/2,128)
    for ch,(x0,x1) in [('盞',(633,682)),('閒',(706,751)),('滿',(891,940)),('紙',(963,1011)),('熱',(1033,1082)),('聞',(1106,1151))]:
        paste_center(A,g(ch,48,sub_stroke,dil_sub),(x0+x1)/2,287)
    a[:,:,3]=np.array(A); r=a[20:320,300:1400]; r[:,:,:3]=np.where((r[:,:,3]>0)[...,None],np.array([66,66,66],np.uint8),r[:,:,:3]); o=Image.fromarray(a); o.save(out+'.png')
    bg=Image.new('RGBA',o.size,(255,255,255,255)); bg.alpha_composite(o); bg.convert('RGB').crop((300,0,1400,340)).save(out+'_preview.png')
build(SONGTI,2,0.025,0.03,0,0,'imgwork/newspaper_songti')
build('payload/sourcehan_4054.otf',0,0.0,0.0,7,3,'imgwork/newspaper_sourcehan')
