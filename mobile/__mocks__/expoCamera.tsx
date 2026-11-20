// Jest stand-in for expo-camera (native module, untranspiled ESM).
import React from 'react';
import { View } from 'react-native';

export const CameraView = (props: any) => <View {...props} />;
export const useCameraPermissions = () => [{ granted: false, canAskAgain: true }, async () => ({ granted: false })];
