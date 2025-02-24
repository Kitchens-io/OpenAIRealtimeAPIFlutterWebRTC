import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

class FirstPage extends StatefulWidget{
   @override
  _FirstPageState createState() => _FirstPageState();
}
class _FirstPageState extends State<FirstPage> {
  final GlobalKey<StatusButton> buttonKey = GlobalKey<StatusButton>();

//1. Call connectWebRTC when the page is loaded
@override
void initState(){
  super.initState();
  print("1. Page loaded");
  buttonKey?.currentState?.setConnecting();
  WidgetsBinding.instance.addPostFrameCallback((_) async{
    getOpenAIWebSocketSecretKey(successBlock: (response){
      String client_secret = response["client_secret"]["value"] ?? "";
      print("1. OpenAI Key fetched successfully: $client_secret");
      connectWebRTC(client_secret);
    }, failBlock: (){
      print("1. Failed to fetch OpenAI Key");
    });
  });
}

//1. Initialize WebRTC
RTCPeerConnection? peerConnection;
RTCDataChannel? dataChannel;
MediaStream? localStream;

//2. connectWebRTC();
Future<void> connectWebRTC(String key) async{
  print("2. Starting connection to PeerConnection");
  try{
    //2.1. Initialize peerConnection
    peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
    ],});
     if (peerConnection != null){
      print("2.1. Initialized peerConnection successfully:${peerConnection!}");
     }else{
      print("2.2. Failed to initialize peerConnection");
      buttonKey?.currentState?.setNotConnect();
       return;
     }

    //2.2. Add local audio stream
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
      'mandatory': {
        'googNoiseSuppression': true, // Noise suppression
        'googEchoCancellation': true, // Echo cancellation
        'googAutoGainControl': true, // Auto gain control
        'minSampleRate': 16000,      // Minimum sample rate (Hz)
        'maxSampleRate': 48000,      // Maximum sample rate (Hz)
        'minBitrate': 32000,         // Minimum bitrate (bps)
        'maxBitrate': 128000,        // Maximum bitrate (bps)
      },

      'optional': [
        {'googHighpassFilter': true}, // High-pass filter, enhances voice quality
       ],
    });
    if (localStream != null){
      print("2.2. Added local audio stream successfully:${localStream!}");
    }else{
      print("2.2. Failed to add local audio stream");
      buttonKey?.currentState?.setNotConnect();
      return;
    }
    localStream!.getTracks().forEach((track) {
       peerConnection!.addTrack(track, localStream!);
    });
    //2.3. Create data channel
    dataChannel = await peerConnection!.createDataChannel('oai-events', RTCDataChannelInit());
    if (dataChannel != null){
      print("2.3. Data channel created successfully");
    }else{
      print("2.3. Failed to create data channel");
      buttonKey?.currentState?.setNotConnect();
      return;
    }

    //2.4. Create Offer and set local description
    RTCSessionDescription offer = await peerConnection!.createOffer();
    print("2.4.1--Created offer");
    await peerConnection!.setLocalDescription(offer);
     print("2.4.2--Set local description: ${offer.sdp}");

    //2.5. Send SDP to server
    sendSDPToServer(offer.sdp, key, (remoteSdp) {
      print("2.5--Sent SDP to server successfully: $remoteSdp");
      //2.6. Set RemoteSdp
      try{
        RTCSessionDescription remote_description = RTCSessionDescription(remoteSdp, 'answer');
        peerConnection!.setRemoteDescription(remote_description);
      }catch(erroe1){
        print("2.6 Failed to set RemoteSdp: $erroe1");
        buttonKey?.currentState?.setNotConnect();
      }
    }, () {
      print("2.5--Failed to send SDP to server");
    });
      print("WebRTC Initialized");
    }catch(error){
      print("Failed to initialize WebRTC: $error");
      buttonKey?.currentState?.setNotConnect();
    }

    // Callback method:
    // Received data
    dataChannel?.onMessage = (RTCDataChannelMessage message) {
      if (message.isBinary) {
        print("Callback method--Received binary message of length: ${message.binary?.length}");
      } else {
        print("Callback method--Received text message: ${message.text}");
      }
    };
    peerConnection?.onAddStream = (MediaStream stream) {
        print("Received remote media stream");
        // Get audio tracks
        var audioTracks = stream.getAudioTracks();
        if (audioTracks.isNotEmpty) {
           print("Audio track received");
          // Can be used to play audio stream
          Helper.setSpeakerphoneOn(true);
          buttonKey?.currentState?.setConnected();
        }else{
          buttonKey?.currentState?.setNotConnect();
        }
    };

    dataChannel?.onDataChannelState = (state) {
      print("Data channel state: $state");
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        print("Data channel is open");
        // Initialize context on the data channel by sending a JSON message.
        dataChannel?.send(RTCDataChannelMessage(jsonEncode({
          "event_id": "event_init_recipe_context",
          "type": "conversation.item.create",
          "previous_item_id": null,
          "item": {
              "id": "msg_init_recipe_context",
              "type": "message",
              "role": "user",
              "content": [
                  {
                      "type": "input_text",
                      "text": "You are an digital assistant named Sue helping out a user with cooking their recipe. Your conversation should only be about culinary topics and the recipe."
                  },
                  {
                    "type": "input_text",
                    "text": "The recipe that we will be cooking:\n{\"name\": \"Homemade pumpkin pie\",\"summary\": \"With a combination of heavy cream and whole milk, this pumpkin pie has the creamiest filling, with warm spices and lovely flavor. It's baked in a flaky, buttery single crust.\",\"prepTime\": 40,\"cookTime\": 60,\"servings\": 12,\"createdAt\": \"2025-02-21T21:30:34Z\",\"updatedAt\": \"2025-02-21T21:30:34Z\",\"deletedAt\": null,\"ingredients\": [{\"ingredientId\": 1,\"name\": \"unsalted butter, cold\",\"quantity\": 9,\"unit\": \"tbsp\",\"group\": \"Pie crust\"},{\"ingredientId\": 2,\"name\": \"all-purpose flour\",\"quantity\": 1.25,\"unit\": \"cups\",\"group\": \"Pie crust\"},{\"ingredientId\": 3,\"name\": \"heavy cream\",\"quantity\": 1,\"unit\": \"cup\",\"group\": \"Pie filling\"},{\"ingredientId\": 4,\"name\": \"whole milk\",\"quantity\": 0.5,\"unit\": \"cup\",\"group\": \"Pie filling\"},{\"ingredientId\": 5,\"name\": \"large eggs plus 2 large yolks\",\"quantity\": 3,\"unit\": null,\"group\": \"Pie filling\"},{\"ingredientId\": 6,\"name\": \"vanilla extract\",\"quantity\": 1,\"unit\": \"tsp\",\"group\": \"Pie filling\"},{\"ingredientId\": 7,\"name\": \"pumpkin puree\",\"quantity\": 1,\"unit\": \"15 oz can\",\"group\": \"Pie filling\"},{\"ingredientId\": 8,\"name\": \"brown sugar\",\"quantity\": 0.5,\"unit\": \"cup\",\"group\": \"Pie filling\"},{\"ingredientId\": 9,\"name\": \"maple syrup\",\"quantity\": 0.25,\"unit\": \"cup\",\"group\": \"Pie filling\"},{\"ingredientId\": 10,\"name\": \"ground cinnamon\",\"quantity\": 0.75,\"unit\": \"tsp\",\"group\": \"Pie filling\"},{\"ingredientId\": 11,\"name\": \"ground ginger\",\"quantity\": 0.5,\"unit\": \"tsp\",\"group\": \"Pie filling\"},{\"ingredientId\": 12,\"name\": \"nutmeg\",\"quantity\": 0.25,\"unit\": \"tsp\",\"group\": \"Pie filling\"},{\"ingredientId\": 13,\"name\": \"salt\",\"quantity\": 0.75,\"unit\": \"tsp\",\"group\": \"Pie filling\"}],\"steps\": [{\"stepId\": 1,\"instruction\": \"Cut the butter into slices (8-10 slices per stick). Put the butter in a bowl and place in the freezer. Fill a medium-sized measuring cup up with water, and add plenty of ice. Let both the butter and the ice sit for 5-10 minutes.\",\"group\": \"Pie crust\",\"images\": null,\"note\": \"\"},{\"stepId\": 2,\"instruction\": \"In the bowl of a standing mixer fitted with a paddle attachment, combine the flour, sugar, and salt. Add half of the chilled butter and mix on low, until the butter is just starting to break down, about a minute. Add the rest of the butter and continue mixing, until the butter is broken down and in various sizes. Slowly add the water, a few tablespoons at a time, and mix until the dough starts to come together but still is quite shaggy.\",\"group\": \"Pie crust\",\"images\": null,\"note\": \"If the dough is not coming together, add more water 1 tablespoon at a time until it does.\"},{\"stepId\": 3,\"instruction\": \"Dump the dough out on your work surface and flatten it slightly into a square. Gently fold the dough over onto itself and flatten again. Repeat this process 3 or 4 more times, until all the loose pieces are worked into the dough. Flatten the dough one last time into a circle, and wrap in plastic wrap. Refrigerate for 30 minutes (and up to 2 days) before using.\",\"group\": \"Pie crust\",\"images\": [\r\n            \t\"\/path-to-step-3-1.jpg\"],\"note\": \"\"},{\"stepId\": 4,\"instruction\": \"Adjust oven rack to lowest position, place rimmed baking sheet on rack, and heat oven to 400\u00B0F. Remove dough from refrigerator and roll out on generously floured (up to 1\/4 cup) work surface to 12-inch circle about 1\/8 inch thick. Roll dough loosely around rolling pin and unroll into pie plate, leaving at least 1-inch overhang on each side. Ease dough into plate by gently lifting edge of dough with one hand while pressing into plate bottom with the other.\",\"group\": \"Pie crust\",\"images\": null,\"note\": \"\"},{\"stepId\": 5,\"instruction\": \"Preheat oven to 400F. While the pie shell is baking, whisk cream, milk, eggs, yolks, and vanilla together in medium bowl. Combine pumpkin puree, sugars, maple syrup, cinnamon, ginger, nutmeg, and salt in large heavy-bottomed saucepan; bring to sputtering simmer over medium heat, 5 to 7 minutes. Continue to simmer pumpkin mixture, stirring constantly until thick and shiny, 10 to 15 minutes.\",\"group\": \"Pie filling\",\"images\": null,\"note\": \"\"},{\"stepId\": 6,\"instruction\": \"Remove pan from heat and stir in the black strap rum if using. Whisk in cream mixture until fully incorporated. Strain the mixture through fine-mesh strainer set over a medium bowl, using a spatula to press the solids through the strainer. Re-whisk the mixture and transfer to warm pre-baked pie shell. Return the pie plate with baking sheet to the oven and bake pie for 10 minutes. Reduce the heat to 300\u00B0F and continue baking until the edges of the pie are set and slightly puffed, and the center jiggles only slightly, 27 to 35 minutes longer. Transfer the pie to wire rack and cool to room temperature, 2 to 3 hours. Cut into wedges and serve with whipped cream.\",\"group\": \"Pie filling\",\"images\": [\r\n            \t\"\/path-to-step-6-1.jpg\",\r\n            \t\"\/path-to-step-6-2.jpg\"],\"note\": \"\"}]\r\n}\r\n"
                  }
              ]
          }
        })));
      }
    };
  }
Future<void> getOpenAIWebSocketSecretKey({
  required Function(Map<String, dynamic>) successBlock,
  required Function() failBlock,
}) async {
  final url = Uri.parse("https://api.openai.com/v1/realtime/sessions");
  const String OPENAI_API_KEY =
      "";

  final body = jsonEncode({
    "model": "gpt-4o-realtime-preview-2024-12-17",
    "voice": "verse",
  });

  try {
    final response = await http.post(
      url,
      headers: {
        "Authorization": "Bearer $OPENAI_API_KEY",
        "Content-Type": "application/json",
      },
      body: body,
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      //print("Network request successful, response content: $jsonResponse");
      if (jsonResponse is Map<String, dynamic>) {
        successBlock(jsonResponse);
      } else {
        failBlock();
      }
    } else {
      //print("Network request failed, status code: ${response.statusCode}, response body: ${response.body}");
      failBlock();
    }
  } catch (e) {
    print("getOpenAIWebSocketSecretKey -- fail: $e");
    failBlock();
  }
 }

Future<void> sendSDPToServer(String? sdp, String key, Function(String) onSuccess, Function() onFailure) async {
  final url = Uri.parse("https://api.openai.com/v1/realtime");
  try {
    final client = HttpClient();
    final request = await client.postUrl(url);

    // Set request headers
    request.headers.set("Authorization", "Bearer $key");
    request.headers.set("Content-Type", "application/sdp");

    // Write request body
    request.write(sdp);

    // Send request and get response
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    print("Network request successful, response content: $responseBody");
    if (responseBody.length > 0){
         onSuccess(responseBody);
    }else{
         onFailure();
    }
  } catch (e) {
    print("catch-->${e.toString()}");
    onFailure();
  }
}
@override
  Widget build(BuildContext context) {
    //ContentChangingButton()
    // Create GlobalKey

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child:ContentChangingButton(key: buttonKey),
      ),
    );
  }
}

 // Button -- carrying variable data
class ContentChangingButton extends StatefulWidget {
  final GlobalKey<StatusButton> key;
  ContentChangingButton({required this.key}) : super(key: key);
  @override
  StatusButton createState() => StatusButton();
}
class StatusButton extends State<ContentChangingButton> {
  // Initial button text
   String buttonText = "WebRTC: connecting";
   String connected_status = "connecting";// not connect / connecting / connected
  // Button click event
  void clickStatusButton(){
    print("Button clicked");
  }
  // External control:
  void setConnected() {
    connected_status = "connected";
    refreshStatusButton();
  }
  // External control:
  void setConnecting() {
    connected_status = "connecting";
    refreshStatusButton();
  }
  // External control:
  void setNotConnect() {
    connected_status = "not connect";
    refreshStatusButton();
  }

  void refreshStatusButton(){
   setState(() {
    if (connected_status == "not connect"){
      buttonText = "WebRTC: not connect";
    }else if (connected_status == "connecting"){
      buttonText = "WebRTC: connecting";
    }else if (connected_status == "connected"){
      buttonText = "WebRTC: connected";
    }
   });
}
    @override
    Widget build(BuildContext context) {
      return ElevatedButton(
        onPressed: clickStatusButton, // Set button click event
        child: Text(buttonText), // Display the text content on the button
      );
    }
  }
