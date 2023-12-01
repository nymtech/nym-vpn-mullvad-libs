import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useParams } from 'react-router';

import {
  AccessMethod,
  AccessMethodSetting,
  NewAccessMethodSetting,
  RelayProtocol,
  ShadowsocksAccessMethod,
  Socks5LocalAccessMethod,
  Socks5RemoteAccessMethod,
} from '../../shared/daemon-rpc-types';
import { messages } from '../../shared/gettext';
import { useAppContext } from '../context';
import { useHistory } from '../lib/history';
import { IpAddress } from '../lib/ip';
import { useSelector } from '../redux/store';
import * as Cell from './cell';
import { SettingsForm, useSettingsFormSubmittable } from './cell/SettingsForm';
import { SettingsGroup } from './cell/SettingsGroup';
import { SettingsRadioGroup } from './cell/SettingsRadioGroup';
import { SettingsRow } from './cell/SettingsRow';
import { SettingsSelect, SettingsSelectItem } from './cell/SettingsSelect';
import { SettingsNumberInput, SettingsTextInput } from './cell/SettingsTextInput';
import { BackAction } from './KeyboardNavigation';
import { Layout, SettingsContainer } from './Layout';
import { NavigationBar, NavigationContainer, NavigationItems, TitleBarItem } from './NavigationBar';
import SettingsHeader, { HeaderSubTitle, HeaderTitle } from './SettingsHeader';
import { StyledContent, StyledNavigationScrollbars, StyledSettingsContent } from './SettingsStyles';
import { SmallButton, SmallButtonGroup } from './SmallButton';

export function EditApiAccessMethod() {
  return (
    <SettingsForm>
      <AccessMethodForm></AccessMethodForm>
    </SettingsForm>
  );
}

function AccessMethodForm() {
  const { id } = useParams<{ id: string | undefined }>();
  const history = useHistory();
  const { addApiAccessMethod, updateApiAccessMethod } = useAppContext();
  const methods = useSelector((state) => state.settings.apiAccessMethods);

  const method = methods.find((method) => method.id === id);

  const newMethod = useRef<NewAccessMethodSetting | undefined>(method);
  const updateMethod = useCallback(
    (method: NewAccessMethodSetting) => (newMethod.current = method),
    [],
  );

  const formSubmittable = useSettingsFormSubmittable();

  const onAdd = useCallback(() => {
    if (newMethod.current !== undefined) {
      if (id === undefined) {
        void addApiAccessMethod(newMethod.current);
      } else {
        void updateApiAccessMethod({ ...newMethod.current, id });
      }
      history.pop();
    }
  }, [newMethod, id, history.pop]);

  const title = getTitle(id !== undefined);
  const subtitle = getSubtitle(id !== undefined);

  return (
    <BackAction action={history.pop}>
      <Layout>
        <SettingsContainer>
          <NavigationContainer>
            <NavigationBar>
              <NavigationItems>
                <TitleBarItem>{title}</TitleBarItem>
              </NavigationItems>
            </NavigationBar>

            <StyledNavigationScrollbars fillContainer>
              <StyledContent>
                <SettingsHeader>
                  <HeaderTitle>{title}</HeaderTitle>
                  <HeaderSubTitle>{subtitle}</HeaderSubTitle>
                </SettingsHeader>

                <StyledSettingsContent>
                  {id !== undefined && method === undefined ? (
                    <span>Failed to open method</span>
                  ) : (
                    <AccessMethodFormImpl method={method} updateMethod={updateMethod} />
                  )}

                  <SmallButtonGroup>
                    <SmallButton onClick={history.pop}>{messages.gettext('Cancel')}</SmallButton>
                    <SmallButton onClick={onAdd} disabled={!formSubmittable}>
                      {id === undefined ? messages.gettext('Add') : messages.gettext('Save')}
                    </SmallButton>
                  </SmallButtonGroup>
                </StyledSettingsContent>
              </StyledContent>
            </StyledNavigationScrollbars>
          </NavigationContainer>
        </SettingsContainer>
      </Layout>
    </BackAction>
  );
}

function getTitle(isNewMethod: boolean) {
  return isNewMethod
    ? messages.pgettext('api-access-methods-view', 'Add method')
    : messages.pgettext('api-access-methods-view', 'Edit method');
}

function getSubtitle(isNewMethod: boolean) {
  return isNewMethod
    ? messages.pgettext('api-access-methods-view', 'Adding a new API access method also tests it.')
    : messages.pgettext('api-access-methods-view', 'Editing an API access method also tests it.');
}

interface EditApiAccessMethodImplProps {
  method?: AccessMethodSetting;
  updateMethod: (method: NewAccessMethodSetting) => void;
}

function AccessMethodFormImpl(props: EditApiAccessMethodImplProps) {
  const types = useMemo<Array<SettingsSelectItem<AccessMethod['type']>>>(
    () => [
      { value: 'shadowsocks', label: 'Shadowsocks' },
      {
        value: 'socks5-remote',
        label: messages.pgettext('api-access-methods-view', 'SOCKS5 remote'),
      },
      {
        value: 'socks5-local',
        label: messages.pgettext('api-access-methods-view', 'SOCKS5 local'),
      },
    ],
    [],
  );

  const name = useRef(props.method?.name ?? '');
  const updateName = useCallback((value: string) => (name.current = value), []);

  const updateMethod = useCallback((value: AccessMethod) => {
    if (name.current !== '') {
      props.updateMethod({ ...value, name: name.current, enabled: true });
    }
  }, []);

  const [type, setType] = useState(props.method?.type ?? 'shadowsocks');

  return (
    <>
      <SettingsRow label={messages.pgettext('api-access-methods-view', 'Name')}>
        <SettingsTextInput
          defaultValue={name.current}
          placeholder={messages.pgettext('api-access-methods-view', 'Enter name')}
          onUpdate={updateName}
        />
      </SettingsRow>

      <SettingsRow label={messages.pgettext('api-access-methods-view', 'Type')}>
        <SettingsSelect defaultValue={type} onUpdate={setType} items={types} />
      </SettingsRow>

      {type === 'shadowsocks' && (
        <EditShadowsocks
          onUpdate={updateMethod}
          method={props.method?.type === 'shadowsocks' ? props.method : undefined}
        />
      )}
      {type === 'socks5-remote' && (
        <EditSocks5Remote
          onUpdate={updateMethod}
          method={props.method?.type === 'socks5-remote' ? props.method : undefined}
        />
      )}
      {type === 'socks5-local' && (
        <EditSocks5Local
          onUpdate={updateMethod}
          method={props.method?.type === 'socks5-local' ? props.method : undefined}
        />
      )}
    </>
  );
}

interface EditMethodProps<T> {
  method?: T;
  onUpdate: (method: AccessMethod) => void;
}

function EditShadowsocks(props: EditMethodProps<ShadowsocksAccessMethod>) {
  const [ip, setIp] = useState(props.method?.ip ?? '');
  const [port, setPort] = useState(props.method?.port);
  const [password, setPassword] = useState(props.method?.password ?? '');
  const [cipher, setCipher] = useState(props.method?.cipher);

  const ciphers = useMemo(
    () => [
      { value: 'aes-128-cfb', label: 'aes-128-cfb' },
      { value: 'aes-128-cfb1', label: 'aes-128-cfb1' },
      { value: 'aes-128-cfb8', label: 'aes-128-cfb8' },
      { value: 'aes-128-cfb128', label: 'aes-128-cfb128' },
      { value: 'aes-256-cfb', label: 'aes-256-cfb' },
      { value: 'aes-256-cfb1', label: 'aes-256-cfb1' },
      { value: 'aes-256-cfb8', label: 'aes-256-cfb8' },
      { value: 'aes-256-cfb128', label: 'aes-256-cfb128' },
      { value: 'rc4', label: 'rc4' },
      { value: 'rc4-md5', label: 'rc4-md5' },
      { value: 'chacha20', label: 'chacha20' },
      { value: 'salsa20', label: 'salsa20' },
      { value: 'chacha20-ietf', label: 'chacha20-ietf' },
      // AEAD ciphers.
      { value: 'aes-128-gcm', label: 'aes-128-gcm' },
      { value: 'aes-256-gcm', label: 'aes-256-gcm' },
      { value: 'chacha20-ietf-poly1305', label: 'chacha20-ietf-poly1305' },
      { value: 'xchacha20-ietf-poly1305', label: 'xchacha20-ietf-poly1305' },
      { value: 'aes-128-pmac-siv', label: 'aes-128-pmac-siv' },
      { value: 'aes-256-pmac-siv', label: 'aes-256-pmac-siv' },
    ],
    [],
  );

  useEffect(() => {
    if (ip !== '' && port !== undefined && cipher !== undefined) {
      props.onUpdate({
        type: 'shadowsocks',
        ip,
        port,
        password,
        cipher,
      });
    }
  }, [ip, port, password, cipher]);

  return (
    <SettingsGroup title={messages.pgettext('api-access-methods-view', 'Server details')}>
      <SettingsRow
        label={messages.pgettext('api-access-methods-view', 'Server')}
        errorMessage={messages.pgettext(
          'api-access-methods-view',
          'Please enter a valid IPv4 or IPv6 address.',
        )}>
        <SettingsTextInput
          value={ip}
          placeholder={messages.pgettext('api-access-methods-view', 'Enter IP')}
          onUpdate={setIp}
          validate={validateIp}
        />
      </SettingsRow>

      <SettingsRow
        label={messages.pgettext('api-access-methods-view', 'Port')}
        errorMessage={messages.pgettext(
          'api-access-methods-view',
          'Please enter a valid remote server port.',
        )}>
        <SettingsNumberInput
          value={port ?? ''}
          placeholder={messages.pgettext('api-access-methods-view', 'Enter port')}
          onUpdate={setPort}
          validate={validatePort}
        />
      </SettingsRow>

      <SettingsRow label={messages.pgettext('api-access-methods-view', 'Password')}>
        <SettingsTextInput
          value={password}
          placeholder={messages.pgettext('api-access-methods-view', 'Optional')}
          onUpdate={setPassword}
          optionalInForm
        />
      </SettingsRow>

      <SettingsRow label={messages.pgettext('api-access-methods-view', 'Cipher')}>
        <SettingsSelect direction="up" defaultValue={cipher} onUpdate={setCipher} items={ciphers} />
      </SettingsRow>
    </SettingsGroup>
  );
}

function EditSocks5Remote(props: EditMethodProps<Socks5RemoteAccessMethod>) {
  const [ip, setIp] = useState(props.method?.ip ?? '');
  const [port, setPort] = useState(props.method?.port);
  const [authentication, setAuthentication] = useState(props.method?.authentication !== undefined);
  const [username, setUsername] = useState(props.method?.authentication?.username ?? '');
  const [password, setPassword] = useState(props.method?.authentication?.password ?? '');

  useEffect(() => {
    if (ip !== '' && port !== undefined) {
      props.onUpdate({
        type: 'socks5-remote',
        ip,
        port,
        authentication: authentication ? { username, password } : undefined,
      });
    }
  }, [ip, port, username, password]);

  return (
    <SettingsGroup title={messages.pgettext('api-access-methods-view', 'Remote Server')}>
      <SettingsRow
        label={messages.pgettext('api-access-methods-view', 'Server')}
        errorMessage={messages.pgettext(
          'api-access-methods-view',
          'Please enter a valid IPv4 or IPv6 address.',
        )}>
        <SettingsTextInput
          value={ip}
          placeholder={messages.pgettext('api-access-methods-view', 'Enter IP')}
          onUpdate={setIp}
          validate={validateIp}
        />
      </SettingsRow>

      <SettingsRow
        label={messages.pgettext('api-access-methods-view', 'Port')}
        errorMessage={messages.pgettext(
          'api-access-methods-view',
          'Please enter a valid remote server port.',
        )}>
        <SettingsNumberInput
          value={port ?? ''}
          placeholder={messages.pgettext('api-access-methods-view', 'Enter port')}
          onUpdate={setPort}
          validate={validatePort}
        />
      </SettingsRow>

      <SettingsRow label={messages.pgettext('api-access-methods-view', 'Authentication')}>
        <Cell.Switch isOn={authentication} onChange={setAuthentication} />
      </SettingsRow>

      {authentication && (
        <>
          <SettingsRow label={messages.pgettext('api-access-methods-view', 'Username')}>
            <SettingsTextInput
              value={username}
              placeholder={messages.pgettext('api-access-methods-view', 'Optional')}
              onUpdate={setUsername}
              optionalInForm
            />
          </SettingsRow>

          <SettingsRow label={messages.pgettext('api-access-methods-view', 'Password')}>
            <SettingsTextInput
              value={password}
              placeholder={messages.pgettext('api-access-methods-view', 'Optional')}
              onUpdate={setPassword}
              optionalInForm
            />
          </SettingsRow>
        </>
      )}
    </SettingsGroup>
  );
}

function EditSocks5Local(props: EditMethodProps<Socks5LocalAccessMethod>) {
  const [remoteIp, setRemoteIp] = useState(props.method?.remoteIp ?? '');
  const [remotePort, setRemotePort] = useState(props.method?.remotePort);
  const [remoteTransportProtocol, setRemoteTransportProtocol] = useState<RelayProtocol>(
    props.method?.remoteTransportProtocol ?? 'tcp',
  );
  const [localPort, setLocalPort] = useState(props.method?.localPort);

  const remoteTransportProtocols = useMemo<Array<SettingsSelectItem<RelayProtocol>>>(
    () => [
      { value: 'tcp', label: 'TCP' },
      { value: 'udp', label: 'UDP' },
    ],
    [],
  );

  useEffect(() => {
    if (remoteIp !== '' && remotePort !== undefined && localPort !== undefined) {
      props.onUpdate({
        type: 'socks5-local',
        remoteIp,
        remotePort,
        remoteTransportProtocol,
        localPort,
      });
    }
  }, [remoteIp, remotePort, localPort, remoteTransportProtocol]);

  return (
    <>
      <SettingsGroup
        title={messages.pgettext('api-access-methods-view', 'Local SOCKS5 server')}
        infoMessage={messages.pgettext(
          'api-access-methods-view',
          'The TCP port where your local SOCKS5 server is listening.',
        )}>
        <SettingsRow
          label={messages.pgettext('api-access-methods-view', 'Port')}
          errorMessage={messages.pgettext(
            'api-access-methods-view',
            'Please enter a valid localhost port.',
          )}>
          <SettingsNumberInput
            value={localPort}
            placeholder={messages.pgettext('api-access-methods-view', 'Enter port')}
            onUpdate={setLocalPort}
            validate={validatePort}
          />
        </SettingsRow>
      </SettingsGroup>

      <SettingsGroup
        title={messages.pgettext('api-access-methods-view', 'Remote Server')}
        infoMessage={[
          messages.pgettext(
            'api-access-methods-view',
            'The app needs the remote server details, where your local SOCKS5 server will forward your traffic.',
          ),
          messages.pgettext(
            'api-access-methods-view',
            'This is needed so our app can allow that traffic in the firewall.',
          ),
        ]}>
        <SettingsRow
          label={messages.pgettext('api-access-methods-view', 'Server')}
          errorMessage={messages.pgettext(
            'api-access-methods-view',
            'Please enter a valid IPv4 or IPv6 address.',
          )}>
          <SettingsTextInput
            value={remoteIp}
            placeholder={messages.pgettext('api-access-methods-view', 'Enter IP')}
            onUpdate={setRemoteIp}
            validate={validateIp}
          />
        </SettingsRow>

        <SettingsRow
          label={messages.pgettext('api-access-methods-view', 'Port')}
          errorMessage={messages.pgettext(
            'api-access-methods-view',
            'Please enter a valid remote server port.',
          )}>
          <SettingsNumberInput
            value={remotePort ?? ''}
            placeholder={messages.pgettext('api-access-methods-view', 'Enter port')}
            onUpdate={setRemotePort}
            validate={validatePort}
          />
        </SettingsRow>

        <SettingsRow label={messages.pgettext('api-access-methods-view', 'Transport protocol')}>
          <SettingsRadioGroup<'tcp' | 'udp'>
            defaultValue={remoteTransportProtocol}
            onUpdate={setRemoteTransportProtocol}
            items={remoteTransportProtocols}
          />
        </SettingsRow>
      </SettingsGroup>
    </>
  );
}

function validateIp(ip: string): boolean {
  try {
    void IpAddress.fromString(ip);
    return true;
  } catch {
    return false;
  }
}

function validatePort(port: number): boolean {
  return port > 0 && port <= 65535;
}
