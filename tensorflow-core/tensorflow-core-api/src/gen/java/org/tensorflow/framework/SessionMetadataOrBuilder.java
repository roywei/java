// Generated by the protocol buffer compiler.  DO NOT EDIT!
// source: tensorflow/core/protobuf/config.proto

package org.tensorflow.framework;

public interface SessionMetadataOrBuilder extends
    // @@protoc_insertion_point(interface_extends:tensorflow.SessionMetadata)
    com.google.protobuf.MessageOrBuilder {

  /**
   * <code>string name = 1;</code>
   */
  java.lang.String getName();
  /**
   * <code>string name = 1;</code>
   */
  com.google.protobuf.ByteString
      getNameBytes();

  /**
   * <pre>
   * The version is optional. If set, needs to be &gt;= 0.
   * </pre>
   *
   * <code>int64 version = 2;</code>
   */
  long getVersion();
}