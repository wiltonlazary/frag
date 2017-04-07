import
  deques,
  events,
  hashes,
  os,
  strutils,
  tables,
  threadpool

import
  sdl2.image as sdl_img

import
  ../assets/asset,
  ../assets/asset_types,
  ../config,
  ../globals,
  ../graphics/two_d/texture,
  ../graphics/two_d/texture_atlas,
  ../graphics/two_d/texture_region,
  ../logger,
  module,
  ../sound/sound

export
  asset,
  asset_types

const maxWorkers = 4

proc init*(this: AssetManager, config: Config): bool =
  let appAssetRoot = if config.assetRoot.isNil: globals.defaultAppAssetRoot
    else: config.assetRoot
  this.assetLoadsInProgress = initTable[Hash, FlowVarBase]()
  this.assetLoadRequests = initDeque[AssetLoadRequest]()
  this.assets = initTable[Hash, ref Asset]()
  this.assetSearchPath = getAppDir() & $DirSep & appAssetRoot & $DirSep
  this.internalSearchPath = getAppDir() & $DirSep & globals.engineAssetRoot & $DirSep
  discard sdl_img.init()
  return true

proc dispose(this: AssetManager, id: Hash) =
  case this.assets[id].assetType
    of AssetType.Texture:
      texture.unload(this.assets[id])
      this.assets.del(id)
    else:
      logWarn "Unable to unload asset with unknown type."

proc shutdown*(this: AssetManager) =
  for id, _ in this.assets:
    this.dispose(id)

  sdl_img.quit()

proc get*[T](this: AssetManager, filename: string): T =
  let id = hash(filename)
  if not this.assets.contains(id):
    logWarn "Asset with filename : " & filename & " not loaded."
    return

  return cast[T](this.assets[id])

proc get*[T](this: AssetManager, id: Hash): T =
  if not this.assets.contains(id):
    logWarn "Asset with id : " & $id & " not loaded."
    return

  return cast[T](this.assets[id])

proc unload*(this: AssetManager, id: Hash) =
  if not this.assets.contains(id):
    logWarn "Asset with filename : " & $id & " not loaded."
    return

  this.dispose(id)

proc unload*(this: AssetManager, filename: string, internal: bool = false) =
  var filepath : string
  if not internal:
    filepath = this.assetSearchPath & filepath
  else:
    filepath = this.internalSearchPath & filename

  let id = hash(filepath)
  if not this.assets.contains(id):
    logWarn "Asset with filepath : " & filepath & " not loaded."
    return

  this.dispose(id)

proc checkLoadingFinished(this: AssetManager): bool =
  if this.assetLoadsInProgress.len > 0 or this.assetLoadRequests.len > 0:
    return false

  return true

proc load*(this: AssetManager, filename: string, assetType: AssetType, internal: bool = false): Hash =
  var filepath : string
  if not internal:
    filepath = this.assetSearchPath & filename
  else:
    filepath = this.internalSearchPath & filename

  if not fileExists(filepath):
    logWarn "File with filepath : " & filepath & " does not exist."
    return

  let newAssetId = hash(filepath)
  if this.assets.contains(newAssetId):
    logWarn "Asset with filepath : " & filepath & " already loaded."
    return

  this.assetLoadRequests.addLast(
    AssetLoadRequest(
      filename: filename,
      filepath: filepath,
      assetId: newAssetId,
      assetType: assetType
    )
  )

  return newAssetId

proc updateLoadsInProgress(this: AssetManager) =
  var asset: ref Asset
  for assetId, assetLoadInProgress in this.assetLoadsInProgress:
    if assetLoadInProgress.isReady:
      if assetLoadInProgress of FlowVar[AtlasInfo]:
          let atlasInfo = cast[FlowVar[AtlasInfo]](assetLoadInProgress).`^`()
        
          let atlasDir = splitFile(atlasInfo.atlas.atlasShortPath).dir
          let texturePath = atlasDir & DirSep &  atlasInfo.atlas.textureFilename

          var textureId = hash(texturePath)
          var atlasTexture = get[Texture](this, textureId)
          if atlasTexture.isNil:
            textureId = this.load(texturePath, AssetType.Texture, false)
        
          this.assets.add(assetId, atlasInfo.atlas)
          this.assetLoadsInProgress.del(assetId)
      else:
        asset = cast[FlowVar[ref Asset]](assetLoadInProgress).`^`()
        case asset.assetType
        of AssetType.Texture:
          let tex = cast[Texture](asset)
          tex.init()

          for assetId, asset in this.assets:
            if asset.assetType == AssetType.TextureAtlas:
              if asset.textureFilepath == tex.filename:
                for regionInfo in asset.regionInfos:
                  asset.regions.add(
                    texture_region.fromTexture(
                      tex,
                      regionInfo.name,
                      regionInfo.w,
                      regionInfo.h,
                      regionInfo.u,
                      regionInfo.u2,
                      regionInfo.v,
                      regionInfo.v2
                    )
                  )

        of AssetType.Sound:
          discard
        of AssetType.TextureRegion:
          echo repr cast[TextureRegion](asset)
        else:
          discard
          
        this.assets.add(assetId, asset)
        this.assetLoadsInProgress.del(assetId)

proc update*(this: AssetManager): bool =
  while this.assetLoadRequests.len > 0 and this.assetLoadsInProgress.len < maxWorkers:
    let nextLoadRequest = this.assetLoadRequests.popFirst()

    case nextLoadRequest.assetType
    of AssetType.Sound:
      this.assetLoadsInProgress.add(nextLoadRequest.assetId, spawn sound.load(nextLoadRequest.filepath))
    of AssetType.Texture:
      this.assetLoadsInProgress.add(nextLoadRequest.assetId, spawn texture.load(nextLoadRequest.filepath))
    of AssetType.TextureRegion:
      logWarn "Cannot load a texture region... Try loading a texture and creating a texture region from it."
      return
    of AssetType.TextureAtlas:
      this.assetLoadsInProgress.add(nextLoadRequest.assetId, spawn texture_atlas.load(nextLoadRequest.filename, nextLoadRequest.filepath))
  
  this.updateLoadsInProgress()
  this.checkLoadingFinished()