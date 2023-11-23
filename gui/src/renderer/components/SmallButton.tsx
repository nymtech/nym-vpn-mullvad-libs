import styled from 'styled-components';

import { colors } from '../../config.json';
import { smallText } from './common-styles';

const StyledSmallButton = styled.button<{ disabled?: boolean }>(smallText, (props) => ({
  height: '32px',
  padding: '5px 16px',
  border: 'none',
  background: props.disabled ? colors.blue50 : colors.blue,
  color: props.disabled ? colors.white50 : colors.white,
  borderRadius: '4px',
  marginLeft: '12px',

  '&&:hover': {
    background: props.disabled ? colors.blue50 : colors.blue60,
  },
}));

interface SmallButtonProps extends Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, 'onClick'> {
  onClick: () => void;
  children: string;
}

export function SmallButton(props: SmallButtonProps) {
  return <StyledSmallButton {...props} />;
}

export const SmallButtonGroup = styled.div<{ $noMarginTop?: boolean }>((props) => ({
  display: 'flex',
  justifyContent: 'end',
  margin: '0 23px',
  marginTop: props.$noMarginTop ? 0 : '30px',
}));
