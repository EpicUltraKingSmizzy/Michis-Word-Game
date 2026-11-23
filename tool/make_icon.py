from PIL import Image, ImageDraw, ImageFont
import sys
FONT='assets/fonts/Montserrat-Black.ttf'
def grad(size, top=(91,200,245), bot=(123,97,255)):
    im=Image.new('RGBA',(size,size))
    d=ImageDraw.Draw(im)
    for y in range(size):
        t=y/(size-1); d.line([(0,y),(size,y)],fill=tuple(int(top[i]+(bot[i]-top[i])*t) for i in range(3))+(255,))
    return im
def tiles(im, size, scale=1.0):
    # 3x2 grid centered; scale shrinks for adaptive safe zone
    d=ImageDraw.Draw(im)
    S=size*scale
    tile=S*0.27; gap=S*0.035
    gw=3*tile+2*gap; gh=2*tile+gap
    x0=(size-gw)/2; y0=(size-gh)/2
    font=ImageFont.truetype(FONT,int(tile*0.62))
    r=tile*0.2; edge=tile*0.07
    for row,letters in enumerate(['MIC','HIS']):
        for col,ch in enumerate(letters):
            x=x0+col*(tile+gap); y=y0+row*(tile+gap)
            d.rounded_rectangle([x,y+edge,x+tile,y+tile+edge],r,fill=(36,6,58,255))
            d.rounded_rectangle([x,y,x+tile,y+tile],r,fill=(59,15,92,255))
            d.text((x+tile/2,y+tile/2+tile*0.02),ch,font=font,fill='white',anchor='mm')
    return im
# full icon
im=grad(1024); tiles(im,1024,0.92); im.convert('RGB').save('assets/icon/app_icon.png')
# adaptive: background + foreground (safe zone ~66%)
grad(1024).convert('RGB').save('assets/icon/adaptive_bg.png')
fg=Image.new('RGBA',(1024,1024),(0,0,0,0)); tiles(fg,1024,0.66); fg.save('assets/icon/adaptive_fg.png')
