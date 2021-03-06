import 'dart:async';

import 'package:animator/animator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dilena/models/user.dart';
import 'package:dilena/pages/activity_feed.dart';
import 'package:dilena/pages/comments.dart';
import 'package:dilena/pages/home.dart';
import 'package:dilena/widgets/custom_image.dart';
import 'package:dilena/widgets/progress.dart';
import 'package:flutter/material.dart';

class Post extends StatefulWidget {
  final String postId;
  final String ownerId;
  final String username;
  final String location;
  final String description;
  final String mediaUrl;
  final dynamic likes;

  Post(
      {this.postId,
      this.ownerId,
      this.username,
      this.location,
      this.description,
      this.mediaUrl,
      this.likes});

  factory Post.fromDocument(DocumentSnapshot doc) {
    return Post(
      postId: doc["postId"],
      ownerId: doc["ownerId"],
      username: doc["username"],
      location: doc["location"],
      description: doc["description"],
      mediaUrl: doc["mediaUrl"],
      likes: doc["likes"],
    );
  }

  int getLikeCount(likes) {
    // if no likes, return 0
    if (likes == null) {
      return 0;
    } else {
      int count = 0;
      // if the key is explicitly set to true, add a like
      likes.values.forEach((value) {
        if (value == true) {
          count += 1;
        }
      });

      return count;
    }
  }

  @override
  _PostState createState() => _PostState(
      postId: this.postId,
      ownerId: this.ownerId,
      username: this.username,
      location: this.location,
      description: this.description,
      mediaUrl: this.mediaUrl,
      likes: this.likes,
      likeCount: getLikeCount(this.likes));
}

class _PostState extends State<Post> {
  final currentUserId = currentUser?.id;
  final String postId;
  final String ownerId;
  final String username;
  final String location;
  final String description;
  final String mediaUrl;
  bool showHeart = false;
  int likeCount;
  Map likes;
  bool isLiked;

  _PostState(
      {this.postId,
      this.ownerId,
      this.username,
      this.location,
      this.description,
      this.mediaUrl,
      this.likes,
      this.likeCount});

  FutureBuilder buildPostHeader() {
    return FutureBuilder(
      future: usersRef.document(ownerId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return circularProgress();
        }
        User user = User.fromDocument(snapshot.data);
        // isPostOwner
        bool isPostOwner = currentUserId == ownerId;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.grey,
            backgroundImage: CachedNetworkImageProvider(user.photoUrl),
          ),
          title: GestureDetector(
            child: Text(
              user.username,
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: () {
              showProfile(context, profileId: user.id);
            },
          ),
          subtitle: Text(location),
          trailing: isPostOwner
              ? IconButton(
                  icon: Icon(Icons.more_vert),
                  onPressed: () {
                    handleDeletePost(context);
                  },
                )
              : Container(
                  width: 0.0,
                  height: 0.0,
                ),
        );
      },
    );
  }

  handleDeletePost(BuildContext parentContext) {
    return showDialog(
        context: parentContext,
        builder: (context) {
          return SimpleDialog(
            title: Text("Apagar esta Publicação?"),
            children: <Widget>[
              SimpleDialogOption(
                onPressed: () {
                  Navigator.of(context).pop();
                  deletePost();
                },
                child: Text(
                  "Apagar",
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
              SimpleDialogOption(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text(
                  "Cancelar",
                ),
              ),
            ],
          );
        });
  }

// note: to delete a post, owner and currentUserId must be equal.
  deletePost() async {
    // delete post itself
    postsRef
        .document(ownerId)
        .collection("userPosts")
        .document(postId)
        .get()
        .then((doc) {
      if (doc.exists) {
        doc.reference.delete();
      }
    });
    // delete uploaded image for the post
    storageRef.child("post_$postId.jpg").delete();
    // delete all activity feed notifications
    QuerySnapshot activityFeedSnapshot = await activityFeedRef
        .document(ownerId)
        .collection("feedItems")
        .where("postId", isEqualTo: postId)
        .getDocuments();

    activityFeedSnapshot.documents.forEach((doc) {
      if (doc.exists) {
        doc.reference.delete();
      }
    });
    // delete all comments
    QuerySnapshot commentsRefSnapshot = await commentsRef
        .document(postId)
        .collection("comments")
        .getDocuments();
    commentsRefSnapshot.documents.forEach((doc) {
      if (doc.exists) {
        doc.reference.delete();
      }
    });
  }

  handleLikePost() {
    bool _isLiked = likes[currentUserId] == true;

    if (_isLiked) {
      postsRef
          .document(ownerId)
          .collection("userPosts")
          .document(postId)
          .updateData({"likes.$currentUserId": false});
      removeLikeFromActivityFeed();
      setState(() {
        likeCount -= 1;
        isLiked = false;
        likes[currentUserId] = false;
      });
    } else if (!_isLiked) {
      postsRef
          .document(ownerId)
          .collection("userPosts")
          .document(postId)
          .updateData({"likes.$currentUserId": true});
      addLikeToActivityFeed();
      setState(() {
        likeCount += 1;
        isLiked = true;
        likes[currentUserId] = true;
        showHeart = true;
      });
      Timer(Duration(milliseconds: 500), () {
        setState(() {
          showHeart = false;
        });
      });
    }
  }

  addLikeToActivityFeed() {
    // add a notification to the post owner's activity  feed only if comment by other users (to avoid get notification for our own like)
    bool isNotPostOwner = currentUserId != ownerId;
    if (isNotPostOwner) {
    return activityFeedRef
        .document(ownerId)
        .collection("feedItems")
        .document(postId)
        .setData({
      "type": "like",
      "username": currentUser.username,
      "userId": currentUser.id,
      "userProfileImage": currentUser.photoUrl,
      "postId": postId,
      "mediaUrl": mediaUrl,
      "timestamp": timestamp
    });
    }
  }

  removeLikeFromActivityFeed() {
    bool isNotPostOwner = currentUserId != ownerId;
    if (isNotPostOwner) {
    return activityFeedRef
        .document(ownerId)
        .collection("feedItems")
        .document(postId)
        .get()
        .then((doc) {
      if (doc.exists) {
        doc.reference.delete();
      }
    });
    }
  }

  GestureDetector buildPostImage() {
    return GestureDetector(
      onDoubleTap: handleLikePost,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          cachedNetworkImage(mediaUrl),
          showHeart
              ? Animator(
                  duration: Duration(milliseconds: 300),
                  tween: Tween(begin: 0.8, end: 1.4),
                  curve: Curves.elasticOut,
                  cycles: 0,
                  builder: (animation) {
                    return Transform.scale(
                      scale: animation.value,
                      child: Icon(
                        Icons.favorite,
                        color: Colors.red,
                        size: 80,
                      ),
                    );
                  },
                )
              : Container(
                  width: 0.0,
                  height: 0.0,
                ),
        ],
      ),
    );
  }

  Column buildPostFooter() {
    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.only(top: 40, left: 20),
            ),
            GestureDetector(
              onTap: handleLikePost,
              child: Icon(
                isLiked ? Icons.favorite : Icons.favorite_border,
                size: 28,
                color: Colors.pink,
              ),
            ),
            Padding(
              padding: EdgeInsets.only(right: 20),
            ),
            GestureDetector(
              onTap: () {
                showComments(
                  context,
                  postId: postId,
                  ownerId: ownerId,
                  mediaUrl: mediaUrl,
                );
              },
              child: Icon(
                Icons.chat,
                size: 28,
                color: Colors.blue[900],
              ),
            ),
          ],
        ),
        Row(
          children: <Widget>[
            Container(
                margin: EdgeInsets.only(left: 20),
                child: Text(
                  "$likeCount gosto",
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                )),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              margin: EdgeInsets.only(left: 20),
              child: Text(
                "$username ",
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: Text(description),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    isLiked = (likes[currentUserId] == true);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        buildPostHeader(),
        buildPostImage(),
        buildPostFooter(),
      ],
    );
  }
}

showComments(BuildContext context,
    {String postId, String ownerId, String mediaUrl}) {
  Navigator.of(context).push(MaterialPageRoute(builder: (context) {
    return Comments(
        postId: postId, postOwnerId: ownerId, postMediaUrl: mediaUrl);
  }));
}
