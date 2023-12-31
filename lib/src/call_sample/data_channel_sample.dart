import 'dart:async';
import 'dart:core';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'signaling.dart';

TextEditingController _textEditingController = TextEditingController();

class DataChannelSample extends StatefulWidget {
  static String tag = 'call_sample';
  final String host;
  const DataChannelSample({super.key, required this.host});

  @override
  DataChannelSampleState createState() => DataChannelSampleState();
}

class DataChannelSampleState extends State<DataChannelSample> {
  Signaling? _signaling;
  List<dynamic> _peers = [];
  String? _selfId;
  bool _inCalling = false;
  RTCDataChannel? _dataChannel;
  Session? _session;
  Timer? _timer;
  var _text = '';
  // ignore: unused_element
  DataChannelSampleState();
  bool _waitAccept = false;

  @override
  initState() {
    super.initState();
    _connect(context);
  }

  @override
  deactivate() {
    super.deactivate();
    _signaling?.close();
    _timer?.cancel();
  }

  Future<bool?> _showAcceptDialog() {
    return showDialog<bool?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('title'),
          content: const Text('accept?'),
          actions: <Widget>[
            MaterialButton(
              child: const Text(
                'Reject',
                style: TextStyle(color: Colors.red),
              ),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            MaterialButton(
              child: const Text(
                'Accept',
                style: TextStyle(color: Colors.green),
              ),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _showInvateDialog() {
    return showDialog<bool?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('title'),
          content: const Text('waiting'),
          actions: <Widget>[
            TextButton(
              child: const Text('cancel'),
              onPressed: () {
                Navigator.of(context).pop(false);
                _hangUp();
              },
            ),
          ],
        );
      },
    );
  }

  void _connect(BuildContext context) async {
    _signaling ??= Signaling(widget.host, context)..connect();

    _signaling?.onDataChannelMessage = (_, dc, RTCDataChannelMessage data) {
      setState(() {
        if (data.isBinary) {
          debugPrint('Got binary [${data.binary}]');
        } else {
          _text = data.text;
        }
      });
    };

    _signaling?.onDataChannel = (_, channel) {
      _dataChannel = channel;
    };

    _signaling?.onSignalingStateChange = (SignalState state) {
      switch (state) {
        case SignalState.closed:
        case SignalState.error:
        case SignalState.open:
          break;
      }
    };

    _signaling?.onCallStateChange = (Session session, CallState state) async {
      switch (state) {
        case CallState.newCall:
          setState(() {
            _session = session;
          });
          // _timer = Timer.periodic(const Duration(seconds: 1), _handleDataChannelTest);
          break;
        case CallState.bye:
          if (_waitAccept) {
            debugPrint('peer reject');
            _waitAccept = false;
            Navigator.of(context).pop(false);
          }
          setState(() {
            _inCalling = false;
          });
          _timer?.cancel();
          _dataChannel = null;
          _inCalling = false;
          _session = null;
          _text = '';
          break;
        case CallState.invite:
          _waitAccept = true;
          _showInvateDialog();
          break;
        case CallState.connected:
          if (_waitAccept) {
            _waitAccept = false;
            Navigator.of(context).pop(false);
          }
          setState(() {
            _inCalling = true;
          });
          break;
        case CallState.ringing:
          bool? accept = await _showAcceptDialog();
          if (accept!) {
            _accept();
            setState(() {
              _inCalling = true;
            });
          } else {
            _reject();
          }

          break;
      }
    };

    _signaling?.onPeersUpdate = ((event) {
      setState(() {
        _selfId = event['self'];
        _peers = event['peers'];
      });
    });
  }

  _handleDataChannelTest(String text) async {
    // String text = 'Say hello ${timer.tick} times, from [$_selfId]';
    // _dataChannel?.send(RTCDataChannelMessage.fromBinary(Uint8List(timer.tick + 1)));
    _dataChannel?.send(RTCDataChannelMessage(text));
  }

  _invitePeer(context, peerId) async {
    if (peerId != _selfId) {
      _signaling?.invite(peerId, 'data', false);
    }
  }

  _accept() {
    if (_session != null) {
      _signaling?.accept(_session!.sid, 'data');
    }
  }

  _reject() {
    if (_session != null) {
      _signaling?.reject(_session!.sid);
    }
  }

  _hangUp() {
    _signaling?.bye(_session!.sid);
  }

  _buildRow(context, peer) {
    var self = (peer['id'] == _selfId);
    return ListBody(children: <Widget>[
      ListTile(
        title: Text(self
            ? peer['name'] + ', ID: ${peer['id']} ' + ' [Your self]'
            : peer['name'] + ', ID: ${peer['id']} '),
        onTap: () => _invitePeer(context, peer['id']),
        trailing: const Icon(Icons.sms),
        subtitle: Text('[${peer['user_agent']}]'),
      ),
      const Divider()
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            'Data Channel Sample${_selfId != null ? ' [Your ID ($_selfId)] ' : ''}'),
        actions: const <Widget>[
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: null,
            tooltip: 'setup',
          ),
        ],
      ),
      floatingActionButton: _inCalling
          ? FloatingActionButton(
              onPressed: _hangUp,
              tooltip: 'Hangup',
              child: const Icon(Icons.call_end),
            )
          : null,
      body: _inCalling
          ? Column(
              children: [
                SizedBox(
                  height: 200,
                  width: double.infinity,
                  child: Card(
                    child: Text(_text),
                  ),
                ),
                SizedBox(
                  height: 60,
                  width: double.infinity,
                  child: TextFormField(
                    maxLines: 2,
                    controller: _textEditingController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Message',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () async {
                    _handleDataChannelTest(_textEditingController.text);
                    _textEditingController.clear();
                  },
                ),
              ],
            )
          : ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.all(0.0),
              itemCount: _peers.length,
              itemBuilder: (context, i) {
                return _buildRow(context, _peers[i]);
              },
            ),
    );
  }
}
