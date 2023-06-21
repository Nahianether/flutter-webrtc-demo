import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../utils/screen_select_dialog.dart';
import 'random_string.dart';

import '../utils/device_info.dart' if (dart.library.js) '../utils/device_info_web.dart';
import '../utils/websocket.dart' if (dart.library.js) '../utils/websocket_web.dart';
import '../utils/turn.dart' if (dart.library.js) '../utils/turn_web.dart';

enum VideoSource { camera, screen }

enum SignalState { open, closed, error }

enum CallState { newCall, ringing, invite, connected, bye }

class Session {
  Session({required this.sid, required this.pid});

  String pid;
  String sid;
  RTCDataChannel? dc;
  RTCPeerConnection? pc;
  final remoteCandidates = <RTCIceCandidate>[];
}

class Signaling {
  Signaling(this._host, this._context);

  final BuildContext _context;
  final String _host;

  final _encoder = const JsonEncoder();
  final _decoder = const JsonDecoder();
  final _sessions = <String, Session>{};
  final _remoteStreams = <MediaStream>[];
  final _senders = <RTCRtpSender>[];
  final _selfId = randomNumeric(6);
  final _port = 8086;

  var _videoSource = VideoSource.camera;
  var _turnCredential = {};

  MediaStream? _localStream;
  SimpleWebSocket? _socket;

  Function(dynamic event)? onPeersUpdate;
  Function(MediaStream stream)? onLocalStream;
  Function(SignalState state)? onSignalingStateChange;
  Function(Session session, RTCDataChannel dc)? onDataChannel;
  Function(Session session, CallState state)? onCallStateChange;
  Function(Session session, MediaStream stream)? onAddRemoteStream;
  Function(Session session, MediaStream stream)? onRemoveRemoteStream;
  Function(Session session, RTCDataChannel dc, RTCDataChannelMessage data)? onDataChannelMessage;

  final sdpSemantics = 'unified-plan';

  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'url': 'stun:stun.l.google.com:19302'},
    ]
  };

  final Map<String, dynamic> _config = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ]
  };

  final Map<String, dynamic> _dcConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': false,
      'OfferToReceiveVideo': false,
    },
    'optional': [],
  };

  close() async {
    await _cleanSessions();
    _socket?.close();
  }

  void switchCamera() {
    if (_localStream != null) {
      if (_videoSource != VideoSource.camera) {
        for (var sender in _senders) {
          if (sender.track!.kind == 'video') {
            sender.replaceTrack(_localStream!.getVideoTracks()[0]);
          }
        }
        _videoSource = VideoSource.camera;
        onLocalStream?.call(_localStream!);
      } else {
        Helper.switchCamera(_localStream!.getVideoTracks()[0]);
      }
    }
  }

  void switchToScreenSharing(MediaStream stream) {
    if (_localStream != null && _videoSource != VideoSource.screen) {
      for (var sender in _senders) {
        if (sender.track!.kind == 'video') {
          sender.replaceTrack(stream.getVideoTracks()[0]);
        }
      }
      onLocalStream?.call(stream);
      _videoSource = VideoSource.screen;
    }
  }

  void muteMic() {
    if (_localStream != null) {
      bool enabled = _localStream!.getAudioTracks()[0].enabled;
      _localStream!.getAudioTracks()[0].enabled = !enabled;
    }
  }

  void invite(String peerId, String media, bool useScreen) async {
    var sessionId = '$_selfId-$peerId';
    Session session =
        await _createSession(null, peerId: peerId, sessionId: sessionId, media: media, screenSharing: useScreen);
    _sessions[sessionId] = session;
    if (media == 'data') {
      _createDataChannel(session);
    }
    _createOffer(session, media);
    onCallStateChange?.call(session, CallState.newCall);
    onCallStateChange?.call(session, CallState.invite);
  }

  void bye(String sessionId) {
    _send('bye', {
      'session_id': sessionId,
      'from': _selfId,
    });
    var sess = _sessions[sessionId];
    if (sess != null) {
      _closeSession(sess);
    }
  }

  void accept(String sessionId, String media) {
    final session = _sessions[sessionId];
    if (session == null) return;
    _createAnswer(session, media);
  }

  void reject(String sessionId) {
    final session = _sessions[sessionId];
    if (session == null) {
      return;
    }
    bye(session.sid);
  }

  void onMessage(message) async {
    final mapData = message as Map<String, dynamic>;
    var data = mapData['data'];

    switch (mapData['type']) {
      case 'peers':
        {
          List<dynamic> peers = data;
          if (onPeersUpdate != null) {
            Map<String, dynamic> event = <String, dynamic>{};
            event['self'] = _selfId;
            event['peers'] = peers;
            onPeersUpdate?.call(event);
          }
        }
        break;
      case 'offer':
        {
          var peerId = data['from'];
          var description = data['description'];
          var media = data['media'];
          var sessionId = data['session_id'];
          var session = _sessions[sessionId];
          var newSession =
              await _createSession(session, peerId: peerId, sessionId: sessionId, media: media, screenSharing: false);
          _sessions[sessionId] = newSession;
          await newSession.pc?.setRemoteDescription(RTCSessionDescription(description['sdp'], description['type']));
          // await _createAnswer(newSession, media);

          if (newSession.remoteCandidates.isNotEmpty) {
            for (final candidate in newSession.remoteCandidates) {
              await newSession.pc?.addCandidate(candidate);
            }
            newSession.remoteCandidates.clear();
          }
          onCallStateChange?.call(newSession, CallState.newCall);
          onCallStateChange?.call(newSession, CallState.ringing);
        }
        break;
      case 'answer':
        {
          var description = data['description'];
          var sessionId = data['session_id'];
          var session = _sessions[sessionId];
          session?.pc?.setRemoteDescription(RTCSessionDescription(description['sdp'], description['type']));
          onCallStateChange?.call(session!, CallState.connected);
        }
        break;
      case 'candidate':
        {
          var peerId = data['from'];
          var candidateMap = data['candidate'];
          var sessionId = data['session_id'];
          var session = _sessions[sessionId];
          RTCIceCandidate candidate =
              RTCIceCandidate(candidateMap['candidate'], candidateMap['sdpMid'], candidateMap['sdpMLineIndex']);

          if (session != null) {
            if (session.pc != null) {
              await session.pc?.addCandidate(candidate);
            } else {
              session.remoteCandidates.add(candidate);
            }
          } else {
            _sessions[sessionId] = Session(pid: peerId, sid: sessionId)..remoteCandidates.add(candidate);
          }
        }
        break;
      case 'leave':
        {
          var peerId = data as String;
          _closeSessionByPeerId(peerId);
        }
        break;
      case 'bye':
        {
          var sessionId = data['session_id'];
          debugPrint('bye: $sessionId');
          var session = _sessions.remove(sessionId);
          if (session != null) {
            onCallStateChange?.call(session, CallState.bye);
            _closeSession(session);
          }
        }
        break;
      case 'keepalive':
        {
          debugPrint('keepalive response!');
        }
        break;
      default:
        break;
    }
  }

  Future<void> connect() async {
    final url = 'https://$_host:$_port/ws';
    _socket = SimpleWebSocket(url);

    debugPrint('connect to $url');

    if (_turnCredential.isEmpty) {
      try {
        _turnCredential = await getTurnCredential(_host, _port);
        _iceServers = {
          'iceServers': [
            {
              'urls': _turnCredential['uris'][0],
              'username': _turnCredential['username'],
              'credential': _turnCredential['password']
            },
          ]
        };
      } catch (e) {
        debugPrint('get turn credential failed: $e');
      }
    }

    _socket?.onOpen = () {
      debugPrint('onOpen');
      onSignalingStateChange?.call(SignalState.open);
      _send('new', {'name': DeviceInfo.label, 'id': _selfId, 'user_agent': DeviceInfo.userAgent});
    };

    _socket?.onMessage = (message) {
      debugPrint('Received data: $message');
      onMessage(_decoder.convert(message));
    };

    _socket?.onClose = (int? code, String? reason) {
      debugPrint('Closed by server [$code => $reason]!');
      onSignalingStateChange?.call(SignalState.closed);
    };

    await _socket?.connect();
  }

  Future<MediaStream> createStream(String media, bool userScreen, {BuildContext? context}) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': userScreen ? false : true,
      'video': userScreen
          ? true
          : {
              'mandatory': {
                'minWidth': '640', // Provide custom width, height and frame rate
                'minHeight': '480',
                'minFrameRate': '30',
              },
              'facingMode': 'user',
              'optional': [],
            }
    };
    late MediaStream stream;
    if (userScreen) {
      if (WebRTC.platformIsDesktop) {
        final source = await showDialog<DesktopCapturerSource>(
          context: context!,
          builder: (context) => ScreenSelectDialog(),
        );
        stream = await navigator.mediaDevices.getDisplayMedia(<String, dynamic>{
          'video': source == null
              ? true
              : {
                  'deviceId': {'exact': source.id},
                  'mandatory': {'frameRate': 30.0}
                }
        });
      } else {
        stream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
      }
    } else {
      stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    }

    onLocalStream?.call(stream);
    return stream;
  }

  Future<Session> _createSession(
    Session? session, {
    required String media,
    required String peerId,
    required String sessionId,
    required bool screenSharing,
  }) async {
    final newSession = session ?? Session(sid: sessionId, pid: peerId);
    if (media != 'data') _localStream = await createStream(media, screenSharing, context: _context);
    debugPrint(_iceServers.toString());
    RTCPeerConnection pc = await createPeerConnection({
      ..._iceServers,
      ...{'sdpSemantics': sdpSemantics}
    }, _config);
    if (media != 'data') {
      switch (sdpSemantics) {
        case 'plan-b':
          pc.onAddStream = (MediaStream stream) {
            onAddRemoteStream?.call(newSession, stream);
            _remoteStreams.add(stream);
          };
          await pc.addStream(_localStream!);
          break;
        case 'unified-plan':
          // Unified-Plan
          pc.onTrack = (event) {
            if (event.track.kind == 'video') {
              onAddRemoteStream?.call(newSession, event.streams[0]);
            }
          };
          _localStream!.getTracks().forEach((track) async {
            _senders.add(await pc.addTrack(track, _localStream!));
          });
          break;
      }
    }
    pc.onIceCandidate = (candidate) async {
      // This delay is needed to allow enough time to try an ICE candidate
      // before skipping to the next one. 1 second is just an heuristic value
      // and should be thoroughly tested in your own environment.
      await Future.delayed(
          const Duration(seconds: 1),
          () => _send('candidate', {
                'to': peerId,
                'from': _selfId,
                'candidate': {
                  'sdpMLineIndex': candidate.sdpMLineIndex,
                  'sdpMid': candidate.sdpMid,
                  'candidate': candidate.candidate,
                },
                'session_id': sessionId,
              }));
    };

    pc.onDataChannel = (channel) => _addDataChannel(newSession, channel);

    pc.onIceConnectionState = (state) {};

    pc.onRemoveStream = (stream) {
      onRemoveRemoteStream?.call(newSession, stream);
      _remoteStreams.removeWhere((it) => (it.id == stream.id));
    };

    return newSession..pc = pc;
  }

  void _addDataChannel(Session session, RTCDataChannel channel) {
    channel.onDataChannelState = (e) {};
    channel.onMessage = (RTCDataChannelMessage data) {
      onDataChannelMessage?.call(session, channel, data);
    };
    session.dc = channel;
    onDataChannel?.call(session, channel);
  }

  Future<void> _createDataChannel(Session session, {label = 'fileTransfer'}) async {
    RTCDataChannelInit dataChannelDict = RTCDataChannelInit()..maxRetransmits = 30;
    RTCDataChannel channel = await session.pc!.createDataChannel(label, dataChannelDict);
    _addDataChannel(session, channel);
  }

  Future<void> _createOffer(Session session, String media) async {
    try {
      RTCSessionDescription s = await session.pc!.createOffer(media == 'data' ? _dcConstraints : {});
      await session.pc!.setLocalDescription(_fixSdp(s));
      _send('offer', {
        'from': _selfId,
        'to': session.pid,
        'description': {'sdp': s.sdp, 'type': s.type},
        'session_id': session.sid,
        'media': media,
      });
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  RTCSessionDescription _fixSdp(RTCSessionDescription s) {
    var sdp = s.sdp;
    s.sdp = sdp!.replaceAll('profile-level-id=640c1f', 'profile-level-id=42e032');
    return s;
  }

  Future<void> _createAnswer(Session session, String media) async {
    try {
      RTCSessionDescription s = await session.pc!.createAnswer(media == 'data' ? _dcConstraints : {});
      await session.pc!.setLocalDescription(_fixSdp(s));
      _send('answer', {
        'to': session.pid,
        'from': _selfId,
        'description': {'sdp': s.sdp, 'type': s.type},
        'session_id': session.sid,
      });
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  _send(event, data) {
    var request = {};
    request['type'] = event;
    request['data'] = data;
    _socket?.send(_encoder.convert(request));
  }

  Future<void> _cleanSessions() async {
    if (_localStream != null) {
      _localStream!.getTracks().forEach((element) async {
        await element.stop();
      });
      await _localStream!.dispose();
      _localStream = null;
    }
    _sessions.forEach((key, sess) async {
      await sess.pc?.close();
      await sess.dc?.close();
    });
    _sessions.clear();
  }

  void _closeSessionByPeerId(String peerId) {
    late Session session;
    _sessions.removeWhere((String key, Session sess) {
      var ids = key.split('-');
      session = sess;
      return peerId == ids[0] || peerId == ids[1];
    });
    _closeSession(session);
    onCallStateChange?.call(session, CallState.bye);
  }

  Future<void> _closeSession(Session session) async {
    _localStream?.getTracks().forEach((element) async {
      await element.stop();
    });
    await _localStream?.dispose();
    _localStream = null;

    await session.pc?.close();
    await session.dc?.close();
    _senders.clear();
    _videoSource = VideoSource.camera;
  }
}
