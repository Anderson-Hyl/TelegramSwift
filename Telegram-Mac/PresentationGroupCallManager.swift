import Foundation
import TelegramVoip
import Postbox
import TelegramCore
import TgVoipWebrtc
import SwiftSignalKit


public struct PresentationGroupCallRequestedVideo {
    public enum Quality {
        case thumbnail
        case medium
        case full
    }

    public struct SsrcGroup {
        public var semantics: String
        public var ssrcs: [UInt32]
    }

    public var audioSsrc: UInt32
    public var peerId: Int64
    public var endpointId: String
    public var ssrcGroups: [SsrcGroup]
    public var minQuality: Quality
    public var maxQuality: Quality
}

public extension GroupCallParticipantsContext.Participant {
    var videoEndpointId: String? {
        return self.videoDescription?.endpointId
    }

    var presentationEndpointId: String? {
        return self.presentationDescription?.endpointId
    }
}

extension GroupCallParticipantsContext.Participant {
    func requestedVideoChannel(minQuality: PresentationGroupCallRequestedVideo.Quality, maxQuality: PresentationGroupCallRequestedVideo.Quality) -> PresentationGroupCallRequestedVideo? {
        guard let audioSsrc = self.ssrc else {
            return nil
        }
        guard let videoDescription = self.videoDescription else {
            return nil
        }
        guard let peer = self.peer else {
            return nil
        }

        return PresentationGroupCallRequestedVideo(audioSsrc: audioSsrc, peerId: peer.id.id._internalGetInt64Value(), endpointId: videoDescription.endpointId, ssrcGroups: videoDescription.ssrcGroups.map { group in
            PresentationGroupCallRequestedVideo.SsrcGroup(semantics: group.semantics, ssrcs: group.ssrcs)
        }, minQuality: minQuality, maxQuality: maxQuality)
    }

    func requestedPresentationVideoChannel(minQuality: PresentationGroupCallRequestedVideo.Quality, maxQuality: PresentationGroupCallRequestedVideo.Quality) -> PresentationGroupCallRequestedVideo? {
        guard let audioSsrc = self.ssrc else {
            return nil
        }
        guard let presentationDescription = self.presentationDescription else {
            return nil
        }
        guard let peer = self.peer else {
            return nil
        }
        return PresentationGroupCallRequestedVideo(audioSsrc: audioSsrc, peerId: peer.id.id._internalGetInt64Value(), endpointId: presentationDescription.endpointId, ssrcGroups: presentationDescription.ssrcGroups.map { group in
            PresentationGroupCallRequestedVideo.SsrcGroup(semantics: group.semantics, ssrcs: group.ssrcs)
        }, minQuality: minQuality, maxQuality: maxQuality)
    }
}


final class PresentationCallVideoView {
    public enum Orientation {
        case rotation0
        case rotation90
        case rotation180
        case rotation270
    }
    
    public let holder: AnyObject
    public let view: NSView
    public let setOnFirstFrameReceived: (((Float) -> Void)?) -> Void
    
    public let getOrientation: () -> Orientation
    public let getAspect: () -> CGFloat
    public let setOnOrientationUpdated: (((Orientation, CGFloat) -> Void)?) -> Void
    public let setVideoContentMode:(CALayerContentsGravity)->Void
    public let setOnIsMirroredUpdated: (((Bool) -> Void)?) -> Void
    public let setIsPaused: (Bool) -> Void
    public let renderToSize: (NSSize, Bool) -> Void

    public init(
        holder: AnyObject,
        view: NSView,
        setOnFirstFrameReceived: @escaping (((Float) -> Void)?) -> Void,
        getOrientation: @escaping () -> Orientation,
        getAspect: @escaping () -> CGFloat,
        setVideoContentMode:@escaping(CALayerContentsGravity)->Void,
        setOnOrientationUpdated: @escaping (((Orientation, CGFloat) -> Void)?) -> Void,
        setOnIsMirroredUpdated: @escaping (((Bool) -> Void)?) -> Void,
        setIsPaused: @escaping(Bool)->Void,
        renderToSize: @escaping(NSSize, Bool) -> Void
    ) {
        self.holder = holder
        self.view = view
        self.setOnFirstFrameReceived = setOnFirstFrameReceived
        self.getOrientation = getOrientation
        self.getAspect = getAspect
        self.setOnOrientationUpdated = setOnOrientationUpdated
        self.setOnIsMirroredUpdated = setOnIsMirroredUpdated
        self.setVideoContentMode = setVideoContentMode
        self.setIsPaused = setIsPaused
        self.renderToSize = renderToSize
    }
}


struct PresentationGroupCallSummaryState: Equatable {
    var info: GroupCallInfo?
    var participantCount: Int
    var callState: PresentationGroupCallState
    var topParticipants: [GroupCallParticipantsContext.Participant]
    var activeSpeakers: Set<PeerId>
    init(
        info: GroupCallInfo?,
        participantCount: Int,
        callState: PresentationGroupCallState,
        topParticipants: [GroupCallParticipantsContext.Participant],
        activeSpeakers: Set<PeerId>
    ) {
        self.info = info
        self.participantCount = participantCount
        self.callState = callState
        self.topParticipants = topParticipants
        self.activeSpeakers = activeSpeakers
    }
}



enum RequestOrJoinGroupCallResult {
    case success(GroupCallContext)
    case fail
    case samePeer(GroupCallContext)
}

public enum PresentationGroupCallMuteAction: Equatable {
    case muted(isPushToTalkActive: Bool)
    case unmuted
    
    var isEffectivelyMuted: Bool {
       switch self {
           case let .muted(isPushToTalkActive):
               return !isPushToTalkActive
           case .unmuted:
               return false
       }
   }

}

public struct VideoSources : Equatable {
    public static func == (lhs: VideoSources, rhs: VideoSources) -> Bool {
        if let lhsVideo = lhs.video, let rhsVideo = rhs.video {
            if !lhsVideo.isEqual(rhsVideo) {
                return false
            }
        } else if (lhs.video != nil) != (rhs.video != nil) {
            return false
        }
        if let lhsScreencast = lhs.screencast, let rhsScreencast = rhs.screencast {
            if !lhsScreencast.isEqual(rhsScreencast) {
                return false
            }
        } else if (lhs.screencast != nil) != (rhs.screencast != nil) {
            return false
        }
        if lhs.failed != rhs.failed {
            return false
        }
        return true
    }
    
    var video: VideoSourceMac? = nil
    var screencast: VideoSourceMac? = nil
    
    var failed: Bool = false
    
    var isEmpty: Bool {
        return video == nil && screencast == nil
    }
}

public struct PresentationGroupCallState: Equatable {
    public enum NetworkState {
        case connecting
        case connected
    }
    
    public enum DefaultParticipantMuteState {
        case unmuted
        case muted
    }
    
    public struct ScheduleState : Equatable {
        var date: Int32
        var subscribed: Bool
    }
    
    public var myPeerId: PeerId
    public var networkState: NetworkState
    public var canManageCall: Bool
    public var adminIds: Set<PeerId>
    public var muteState: GroupCallParticipantsContext.Participant.MuteState?
    public var defaultParticipantMuteState: DefaultParticipantMuteState?
    public var recordingStartTimestamp: Int32?
    public var title: String?
    public var raisedHand: Bool
    public var scheduleTimestamp: Int32?
    public var subscribedToScheduled: Bool
    public var isVideoEnabled: Bool
    public var isStream: Bool
    public var isChannel: Bool
    public var isConference: Bool
    
    public var sources: VideoSources = .init()

    
    public init(
        myPeerId: PeerId,
        networkState: NetworkState,
        canManageCall: Bool,
        adminIds: Set<PeerId>,
        muteState: GroupCallParticipantsContext.Participant.MuteState?,
        defaultParticipantMuteState: DefaultParticipantMuteState?,
        recordingStartTimestamp: Int32?,
        title: String?,
        raisedHand: Bool,
        scheduleTimestamp: Int32?,
        subscribedToScheduled: Bool,
        isVideoEnabled: Bool,
        isStream: Bool,
        isChannel: Bool,
        isConference: Bool
    ) {
        self.myPeerId = myPeerId
        self.networkState = networkState
        self.canManageCall = canManageCall
        self.adminIds = adminIds
        self.muteState = muteState
        self.defaultParticipantMuteState = defaultParticipantMuteState
        self.recordingStartTimestamp = recordingStartTimestamp
        self.title = title
        self.raisedHand = raisedHand
        self.scheduleTimestamp = scheduleTimestamp
        self.subscribedToScheduled = subscribedToScheduled
        self.isVideoEnabled = isVideoEnabled
        self.isStream = isStream
        self.isChannel = isChannel
        self.isConference = isConference
    }
    
    var scheduleState: ScheduleState? {
        if let scheduleTimestamp = scheduleTimestamp {
            return .init(date: scheduleTimestamp, subscribed: subscribedToScheduled)
        } else {
            return nil
        }
    }
}
final class PresentationGroupCallMemberEvent {
    let peer: Peer
    let joined: Bool
    
    init(peer: Peer, joined: Bool) {
        self.peer = peer
        self.joined = joined
    }
}




struct PresentationGroupCallMembers: Equatable {
    public var participants: [GroupCallParticipantsContext.Participant]
    public var speakingParticipants: Set<PeerId>
    public var totalCount: Int
    public var loadMoreToken: String?
    
    public init(
        participants: [GroupCallParticipantsContext.Participant],
        speakingParticipants: Set<PeerId>,
        totalCount: Int,
        loadMoreToken: String?
    ) {
        self.participants = participants
        self.speakingParticipants = speakingParticipants
        self.totalCount = totalCount
        self.loadMoreToken = loadMoreToken
    }
}


enum GroupCallVideoMode {
    case video
    case screencast
}

protocol PresentationGroupCall : class {
    

    
    var account: Account { get }
    var engine: TelegramEngine { get }
    var accountContext: AccountContext { get }
    var sharedContext: SharedAccountContext { get }
    var internalId: CallSessionInternalId { get }
    var peerId: PeerId? { get }
    var peer: Peer? { get }
    var joinAsPeerId: PeerId { get }
    var joinAsPeerIdValue:Signal<PeerId, NoError> { get }
    var canBeRemoved: Signal<Bool, NoError> { get }
    var state: Signal<PresentationGroupCallState, NoError> { get }
    var members: Signal<PresentationGroupCallMembers?, NoError> { get }
    var audioLevels: Signal<[(PeerId, UInt32, Float, Bool)], NoError> { get }
    var myAudioLevel: Signal<Float, NoError> { get }
    var invitedPeers: Signal<[PresentationGroupCallInvitedPeer], NoError> { get }
    var isMuted: Signal<Bool, NoError> { get }
    var summaryState: Signal<PresentationGroupCallSummaryState?, NoError> { get }
    var callInfo: Signal<GroupCallInfo?, NoError> { get }
    var stateVersion: Signal<Int, NoError> { get }
    var isSpeaking: Signal<Bool, NoError> { get }
    
    var callId: Int64? { get }
    
    var isStream: Bool { get }
    var isConference: Bool { get }

    var e2eEncryptionKeyHash: Signal<Data?, NoError> { get }

    var mustStopSharing:(()->Void)? { get set }
    var mustStopVideo:(()->Void)? { get set }

//    var activeCall: CachedChannelData.ActiveCall? { get }
    var inviteLinks:Signal<GroupCallInviteLinks?, NoError> { get }

    var permissions:(PresentationGroupCallMuteAction, @escaping(Bool)->Void)->Void { get set }
    
    var displayAsPeers: Signal<[FoundPeer]?, NoError> { get }
    
    func raiseHand()
    func lowerHand()
    func resetListenerLink()

    func leave(terminateIfPossible: Bool) -> Signal<Bool, NoError>
    func toggleIsMuted()
    func setVolume(peerId: PeerId, volume: Int32, sync: Bool)
    func setIsMuted(action: PresentationGroupCallMuteAction)
    func updateMuteState(peerId: PeerId, isMuted: Bool) -> GroupCallParticipantsContext.Participant.MuteState?
    func invitePeer(_ peerId: PeerId, isVideo: Bool) -> Bool
    func kickPeer(id: EnginePeer.Id)
    func removedPeer(_ peerId: PeerId)
    func updateDefaultParticipantsAreMuted(isMuted: Bool)
    
    func setRequestedVideoList(items: [PresentationGroupCallRequestedVideo])
    func makeVideoView(endpointId: String, videoMode: GroupCallVideoMode, completion: @escaping (PresentationCallVideoView?) -> Void)
    func requestVideo(deviceId: OngoingCallVideoCapturer, source: VideoSourceMac)
    func requestVideo(deviceId: String, source: VideoSourceMac)
    func disableVideo()
    func requestScreencast(deviceId: OngoingCallVideoCapturer, source: VideoSourceMac)
    func requestScreencast(deviceId: String, source: VideoSourceMac)
    func disableScreencast()
    
    func toggleVideoFailed(failed: Bool)

    func loadMore()

    func joinAsSpeakerIfNeeded(_ joinHash: String)
    func reconnect(as peerId: PeerId) -> Void
    func updateTitle(_ title: String, force: Bool) -> Void
    func setShouldBeRecording(_ shouldBeRecording: Bool, title: String?, videoOrientation: Bool?) -> Void
    func startScheduled()
    func toggleScheduledSubscription(_ subscribe: Bool)
}



public struct PresentationGroupCallInvitedPeer: Equatable {
    public enum State {
        case requesting
        case ringing
        case connecting
    }
    
    public var id: EnginePeer.Id
    public var state: State?
    
    public init(id: EnginePeer.Id, state: State?) {
        self.id = id
        self.state = state
    }
}

