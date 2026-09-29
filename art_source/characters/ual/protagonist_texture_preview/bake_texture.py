"""Bake generated projection artwork to the unchanged CharacterPaint UV map.

This is a texture-coordinate bake, not geometry generation. The artwork remains
separate and editable; surface_data contains read-only source mesh measurements.
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt, binary_erosion

OUT=Path(__file__).resolve().parent
SIZE=1024
data=np.load(OUT/'surface_data.npz')
positions=data['positions'];triangles=data['triangles'];uvs=data['triangle_uvs'];normals=data['triangle_normals']
art=Image.open(OUT/'painted_projections.png').convert('RGB')
w,h=art.size
projections=[]
registration=[]
for i,name in enumerate(['front','back','face','head_back']):
    source=np.asarray(art.crop((i%2*w//2,i//2*h//2,(i%2+1)*w//2,(i//2+1)*h//2)).resize((1024,1024),Image.Resampling.LANCZOS)).astype(float)
    guide=np.asarray(Image.open(OUT/('guide_'+name+'.png')).convert('RGB')).astype(float)
    # Skin and dark brown hair have chroma; the unchanged background is neutral.
    colored=((source[:,:,0]-source[:,:,2]>12)&(source[:,:,0]>35))|(source.mean(2)<65)
    # Include the charcoal shorts enclosed by the warm silhouette.
    if i<2:
        for y in range(390,570):
            xx=np.where(colored[y])[0]
            if len(xx)>1:
                colored[y,xx.min():xx.max()+1]=True
    orig=guide.mean(2)>122
    for mask in [orig,colored]:
        if not np.any(mask): raise ValueError('Empty projection mask '+name)
    # Only global registration: preserve facial anatomy supplied by the painting.
    oy,ox=np.where(orig);sy,sx=np.where(colored)
    registration.append({'view':name,'template_bbox':[int(ox.min()),int(oy.min()),int(ox.max()),int(oy.max())], 'paint_bbox':[int(sx.min()),int(sy.min()),int(sx.max()),int(sy.max())]})
    # Extrapolate surface colors past the silhouette for grazing-angle UV samples.
    safe=binary_erosion(colored,iterations=2)
    nearest=distance_transform_edt(~safe,return_distances=False,return_indices=True)
    source=source[nearest[0],nearest[1]]
    projections.append(source)
(OUT/'projection_registration.json').write_text(json.dumps(registration,indent=2))

def sample(image,xy):
    q=np.clip(np.rint(xy).astype(int),0,1023)
    return image[q[:,1],q[:,0]]

def paint(p,n):
    front=np.c_[(p[:,0]/2.12+.5)*1024,(.5-(p[:,2]-.915)/2.12)*1024]
    back=front.copy();back[:,0]=1024-front[:,0]
    # Front/back blend stays continuous around the side of each limb.
    weight=np.clip(.5-n[:,1]*1.25,0,1)
    weight=weight*weight*(3-2*weight)
    color=sample(projections[0],front)*weight[:,None]+sample(projections[1],back)*(1-weight[:,None])
    face=np.c_[(p[:,0]/.43+.5)*1024,(.5-(p[:,2]-1.67)/.43)*1024]
    # Both generated close-ups translated the existing head about 55 pixels up.
    # Register the projection, never the mesh, to the measured original silhouette.
    face[:,1]-=55
    rear=face.copy();rear[:,0]=1024-face[:,0]
    head=sample(projections[2],face)*weight[:,None]+sample(projections[3],rear)*(1-weight[:,None])
    t=np.clip((p[:,2]-1.49)/.07,0,1)
    t=t*t*(3-2*t)
    return color*(1-t[:,None])+head*t[:,None]

atlas=np.zeros((SIZE,SIZE,3),dtype=np.float32)
occupied=np.zeros((SIZE,SIZE),dtype=bool)
for ids,uv,ns in zip(triangles,uvs,normals):
    t=uv.copy(); t[:,0]*=SIZE; t[:,1]=(1-t[:,1])*SIZE
    xmin,ymin=np.maximum(np.floor(t.min(0)).astype(int),0)
    xmax,ymax=np.minimum(np.ceil(t.max(0)).astype(int),SIZE-1)
    if xmax<xmin or ymax<ymin:continue
    den=(t[1,1]-t[2,1])*(t[0,0]-t[2,0])+(t[2,0]-t[1,0])*(t[0,1]-t[2,1])
    if abs(den)<1e-8:continue
    yy,xx=np.mgrid[ymin:ymax+1,xmin:xmax+1];x=xx+.5;y=yy+.5
    a=((t[1,1]-t[2,1])*(x-t[2,0])+(t[2,0]-t[1,0])*(y-t[2,1]))/den
    b=((t[2,1]-t[0,1])*(x-t[2,0])+(t[0,0]-t[2,0])*(y-t[2,1]))/den
    c=1-a-b
    mask=(a>=-1e-6)&(b>=-1e-6)&(c>=-1e-6)
    if not np.any(mask):continue
    weights=np.c_[a[mask],b[mask],c[mask]]
    p=weights@positions[ids];n=weights@ns;n/=np.maximum(np.linalg.norm(n,axis=1)[:,None],1e-8)
    atlas[yy[mask],xx[mask]]=paint(p,n)
    occupied[yy[mask],xx[mask]]=True
nearest=distance_transform_edt(~occupied,return_distances=False,return_indices=True)
atlas=atlas[nearest[0],nearest[1]]
image=Image.fromarray(np.clip(atlas,0,255).astype('uint8'))
image=image.resize((512,512),Image.Resampling.BOX)
image.save(OUT/'Protagonist_BaseColor_512.png')
print('Baked',image.size,'UV coverage',round(float(occupied.mean()),4))
print(json.dumps(registration,indent=2))
