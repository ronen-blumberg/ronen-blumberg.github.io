function loadImage1( imagefile as string ) as fb.image ptr
    DIM AS fb.image ptr image
    dim as long ImageWid , ImageHei
    var f = freefile()
    if open( imagefile for binary access read as #f) then
        return NULL
    EndIf
    get #f,19,ImageWid : get #f,,ImageHei
    close #f
    image = IMAGECREATE(ImageWid , ImageHei , 0)    
    bload imagefile, image
    return image
end function

sub ShowImage( image as fb.image ptr )    
    put(0,0), image, pset
End Sub

sub destroyImage( image as fb.image ptr )
    if image then ImageDestroy(image)
End Sub
