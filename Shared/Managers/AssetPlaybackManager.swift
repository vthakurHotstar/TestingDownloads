/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 `AssetPlaybackManager` is the class that manages the playback of Assets in this sample using Key-value observing on various AVFoundation classes.
 */

import UIKit
import AVFoundation

class AssetPlaybackManager: NSObject {
    
    // MARK: Properties
    
    /// Singleton for AssetPlaybackManager.
    static let sharedManager = AssetPlaybackManager()
    
    weak var delegate: AssetPlaybackDelegate?
    
    /// The instance of AVPlayer that will be used for playback of AssetPlaybackManager.playerItem.
    private let player = AVPlayer()
    
    /// A Bool tracking if the AVPlayerItem.status has changed to .readyToPlay for the current AssetPlaybackManager.playerItem.
    private var readyForPlayback = false
    
    /// The `NSKeyValueObservation` for the KVO on \AVPlayerItem.status.
    private var playerItemObserver: NSKeyValueObservation?
    
    /// The `NSKeyValueObservation` for the KVO on \AVURLAsset.isPlayable.
    private var urlAssetObserver: NSKeyValueObservation?
    
    /// The `NSKeyValueObservation` for the KVO on \AVPlayer.currentItem.
    private var playerObserver: NSKeyValueObservation?
    
    /// The AVPlayerItem associated with AssetPlaybackManager.asset.urlAsset
    private var playerItem: AVPlayerItem? {
        willSet {
            /// Remove any previous KVO observer.
            guard let playerItemObserver = playerItemObserver else { return }
            
            playerItemObserver.invalidate()
        }
        
        didSet {
            playerItemObserver = playerItem?.observe(\AVPlayerItem.status, options: [.new, .initial]) { [weak self] (item, _) in
                guard let strongSelf = self else { return }
                print("Status is :: ",item.status.rawValue,item.error)
                item.errorLog()?.events.forEach({ event in
                    print("Event is :: ",event.errorComment,event.errorStatusCode,event.uri)
                })
                if item.status == .readyToPlay {
                    if !strongSelf.readyForPlayback {
                        strongSelf.readyForPlayback = true
                        strongSelf.delegate?.streamPlaybackManager(strongSelf, playerReadyToPlay: strongSelf.player)
                    }
                } else if item.status == .failed {
                    let error = item.error
                    
                    print("Error: \(String(describing: error?.localizedDescription))")
                }
            }
        }
    }
    
    /// The Asset that is currently being loaded for playback.
    private var asset: Asset? {
        willSet {
            /// Remove any previous KVO observer.
            guard let urlAssetObserver = urlAssetObserver else { return }
            
            urlAssetObserver.invalidate()
        }
        
        didSet {
            if let asset = asset {
                urlAssetObserver = asset.urlAsset.observe(\AVURLAsset.isPlayable, options: [.new, .initial]) { [weak self] (urlAsset, _) in
                    guard let strongSelf = self, urlAsset.isPlayable == true else { return }
                    print("Url assset :: ",urlAsset.url)
                    strongSelf.playerItem = AVPlayerItem(asset: urlAsset)
                    strongSelf.player.replaceCurrentItem(with: strongSelf.playerItem)
                }
            } else {
                playerItem = nil
                player.replaceCurrentItem(with: nil)
                readyForPlayback = false
            }
        }
    }
    
    // MARK: Intitialization
    
    override private init() {
        super.init()
        NotificationCenter.default.addObserver(
                            self,
                            selector: #selector(newAccessLogEntered(notificationObj:)),
                            name: NSNotification.Name.AVPlayerItemNewAccessLogEntry,
                            object: nil
                        )
                        NotificationCenter.default.addObserver(
                            self,
                            selector: #selector(newErrorLogEntered(notificationObj:)),
                            name: NSNotification.Name.AVPlayerItemNewErrorLogEntry,
                            object: nil
                        )
        playerObserver = player.observe(\AVPlayer.currentItem, options: [.new]) { [weak self] (player, _) in
            guard let strongSelf = self else { return }
            
            strongSelf.delegate?.streamPlaybackManager(strongSelf, playerCurrentItemDidChange: player)
        }
        
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
    }
    
    @objc
        func newErrorLogEntered(notificationObj: Notification?) {
            if let playerItem = notificationObj?.object as? AVPlayerItem {
                playerItem.errorLog()?.events.forEach { event in
                    print("Error lg :: ", event.errorComment, playerItem.error, event.uri)
                }
            }
        }
    
        @objc
        func newAccessLogEntered(notificationObj: Notification?) {
            let playerItem = notificationObj?.object as? AVPlayerItem
            if let events = playerItem?.accessLog()?.events {
                for e in events.reversed() {
                    print("Accesslog :: ", e.averageVideoBitrate, e.averageAudioBitrate)
                }
            }
        }
    
    deinit {
        /// Remove any KVO observer.
        playerObserver?.invalidate()
    }
    
    /**
     Replaces the currently playing `Asset`, if any, with a new `Asset`. If nil
     is passed, `AssetPlaybackManager` will handle unloading the existing `Asset`
     and handle KVO cleanup.
     */
    func setAssetForPlayback(_ asset: Asset?) {
        self.asset = asset
    }
}

/// AssetPlaybackDelegate provides a common interface for AssetPlaybackManager to provide callbacks to its delegate.
protocol AssetPlaybackDelegate: AnyObject {

    /// This is called when the internal AVPlayer in AssetPlaybackManager is ready to start playback.
    func streamPlaybackManager(_ streamPlaybackManager: AssetPlaybackManager, playerReadyToPlay player: AVPlayer)
    
    /// This is called when the internal AVPlayer's currentItem has changed.
    func streamPlaybackManager(_ streamPlaybackManager: AssetPlaybackManager, playerCurrentItemDidChange player: AVPlayer)
}

