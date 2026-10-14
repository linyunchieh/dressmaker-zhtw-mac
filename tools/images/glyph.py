from PIL import Image, ImageDraw, ImageFont, ImageFilter
import numpy as np
SONGTI='/System/Library/Fonts/Supplemental/Songti.ttc'
PINGFANG='/System/Library/AssetsV2/com_apple_MobileAsset_Font8/86ba2c91f017a3749571a82f2c6d890ac7ffb2fb.asset/AssetData/PingFang.ttc'
def ink(ch, font, index, size, stroke=0):
    f=ImageFont.truetype(font, size, index=index)
    W=size*3; im=Image.new('L',(W,W),0); d=ImageDraw.Draw(im)
    d.text((size,size),ch,font=f,fill=255,stroke_width=stroke,stroke_fill=255)
    bb=im.getbbox(); return im.crop(bb)
def fit(ch, font, index, box_h, stroke_ratio=0.0, ss=4):
    """render ch so that ink height == box_h (supersampled)"""
    size=box_h*ss
    g=ink(ch,font,index,size,int(size*stroke_ratio))
    s=box_h*ss/g.height
    g=ink(ch,font,index,int(size*s),int(size*s*stroke_ratio))
    return g.resize((max(1,round(g.width/ss)),max(1,round(g.height/ss))),Image.LANCZOS)
def paste_center(alpha, g, cx, cy):
    x=round(cx-g.width/2); y=round(cy-g.height/2)
    region=alpha.crop((x,y,x+g.width,y+g.height))
    alpha.paste(Image.fromarray(np.maximum(np.array(region),np.array(g))),(x,y))
