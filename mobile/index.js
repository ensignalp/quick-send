/**
 * @format
 */

import { AppRegistry } from 'react-native';
import { registerRootComponent } from 'expo';
import App from './App';

// "main" for Expo (Go, dev client, web); appName for the native MainActivity.
registerRootComponent(App);
AppRegistry.registerComponent('QuickSendMobile', () => App);
